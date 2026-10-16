/*****************************************************************************
 * vout_scenario.c: testflight for video output pipeline
 *****************************************************************************
 * Copyright (C) 2021 VideoLabs
 *
 * Author: Alexandre Janniaux <ajanni@videolabs.io>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include "video_output.h"

#include <vlc_filter.h>
#include <vlc_vout_display.h>
#include <stdatomic.h>

static struct scenario_data
{
    vlc_sem_t wait_stop;
    struct vlc_video_context *decoder_vctx;
    unsigned display_picture_count;
    bool converter_opened;
    bool display_opened;
    bool test_finished;

    vlc_fourcc_t display_chroma;
    atomic_bool orientation_finished;
    bool filter_requested;
    bool accept_orientation;
    unsigned format_updates;
    bool real_transform;
} scenario_data;

static void decoder_fixed_size(decoder_t *dec, vlc_fourcc_t chroma,
        unsigned width, unsigned height)
{
    dec->fmt_out.video.i_chroma
        = dec->fmt_out.i_codec
        = chroma;
    dec->fmt_out.video.i_visible_width
        = dec->fmt_out.video.i_width
        = width;
    dec->fmt_out.video.i_visible_height
        = dec->fmt_out.video.i_height
        = height;
}

static void decoder_rgba_800_600(decoder_t *dec)
    { decoder_fixed_size(dec, VLC_CODEC_RGBA, 800, 600); }

static void decoder_decode_change_chroma(decoder_t *dec, block_t *block)
{
    if (scenario_data.test_finished)
        goto end;

    static const vlc_fourcc_t chroma_list[] = {
        VLC_CODEC_RGBA,
        VLC_CODEC_I420,
        VLC_CODEC_NV12,
    };

    size_t index = 0;
    while (index < ARRAY_SIZE(chroma_list))
    {
        index++;
        if (chroma_list[index - 1] == dec->fmt_out.video.i_chroma)
            break;
    }

    /* Limit to the last chroma */
    if (index >= ARRAY_SIZE(chroma_list))
        index = ARRAY_SIZE(chroma_list);

    /* Switch to the new chroma */
    dec->fmt_out.video.i_chroma
        = dec->fmt_out.i_codec
        = chroma_list[index];

    int ret = decoder_UpdateVideoOutput(dec, NULL);
    if (ret != 0)
    {
        scenario_data.test_finished = true;
        vlc_sem_post(&scenario_data.wait_stop);
        goto end;
    }

    const picture_resource_t resource = {
        .p_sys = NULL,
    };
    picture_t *pic = picture_NewFromResource(&dec->fmt_out.video, &resource);
    assert(pic);
    pic->date = block->i_pts;
    pic->b_progressive = true;

    /* Simulate the chroma change */
    pic->format.i_chroma = chroma_list[index];
    decoder_QueueVideo(dec, pic);
end:
    block_Release(block);
}

static int display_fixed_size(vout_display_t *vd, video_format_t *fmtp,
        struct vlc_video_context *vctx, vlc_fourcc_t chroma,
        unsigned width, unsigned height)
{
    (void)fmtp; (void)vctx;
    msg_Info(vd, "Setting up the display %4.4s: %ux%u",
             (const char *)&chroma, width, height);

    scenario_data.display_opened = true;
    return VLC_SUCCESS;
}

static int display_fail_second_time(vout_display_t *vd, video_format_t *fmtp,
        struct vlc_video_context *vctx, unsigned width, unsigned height)
{
    (void)vctx;

    vlc_fourcc_t chroma = fmtp->i_chroma;
    if (scenario_data.display_opened)
    {
        msg_Info(vd, "Failing the display %4.4s: %ux%u",
                 (const char *)&chroma, width, height);
        scenario_data.test_finished = true;
        return VLC_EGENERIC;
    }

    return display_fixed_size(vd, fmtp, vctx, chroma, 800, 600);
}

static int display_800_600_fail_second_time(
        vout_display_t *vd, video_format_t *fmtp,
        struct vlc_video_context *vctx)
    { return display_fail_second_time(vd, fmtp, vctx, 800, 600); }

/* A live orientation change must first be offered to the display. Metadata
 * transforms work on hardware pictures too, without a software converter. */
static void decoder_decode_orientation(decoder_t *dec, block_t *block)
{
    if (!atomic_load(&scenario_data.orientation_finished))
    {
        int ret = decoder_UpdateVideoOutput(dec, dec->p_sys);
        assert(ret == VLC_SUCCESS);
        picture_t *picture = picture_NewFromFormat(&dec->fmt_out.video);
        assert(picture != NULL);
        picture->date = block->i_pts;
        picture->b_progressive = true;
        decoder_QueueVideo(dec, picture);
    }
    block_Release(block);
}

static void filter_orientation(filter_t *filter)
{
    assert(filter->b_allow_fmt_out_change);
    filter->fmt_out.video.orientation = ORIENT_ROTATED_90;
}

static int display_orientation_accept(vout_display_t *vd, video_format_t *fmt,
                                      struct vlc_video_context *vctx)
{
    scenario_data.accept_orientation = true;
    return display_fixed_size(vd, fmt, vctx, VLC_CODEC_RGBA, 800, 600);
}

static int display_orientation_reject(vout_display_t *vd, video_format_t *fmt,
                                      struct vlc_video_context *vctx)
{
    scenario_data.accept_orientation = false;
    return display_fixed_size(vd, fmt, vctx, VLC_CODEC_RGBA, 800, 600);
}

static void decoder_context_rgba_800_600(decoder_t *dec)
{
    decoder_rgba_800_600(dec);
    vlc_decoder_device *device = decoder_GetDecoderDevice(dec);
    assert(device != NULL);
    scenario_data.decoder_vctx = vlc_video_context_Create(device,
        VLC_VIDEO_CONTEXT_VAAPI, 0, NULL);
    vlc_decoder_device_Release(device);
    assert(scenario_data.decoder_vctx != NULL);
    dec->p_sys = scenario_data.decoder_vctx;
}

static int display_transform_context(vout_display_t *vd, video_format_t *fmt,
                                     struct vlc_video_context *vctx)
{
    scenario_data.real_transform = true;
    return display_orientation_accept(vd, fmt, vctx);
}

static int display_update_orientation(vout_display_t *vd, const video_format_t *fmt,
                                      struct vlc_video_context *vctx)
{
    VLC_UNUSED(vd); VLC_UNUSED(vctx);
    assert(fmt->orientation == ORIENT_ROTATED_90 ||
           (scenario_data.accept_orientation && fmt->orientation == ORIENT_NORMAL));
    assert(fmt->i_chroma == VLC_CODEC_RGBA);
    if (scenario_data.real_transform)
        assert(vctx == scenario_data.decoder_vctx);
    scenario_data.format_updates++;
    return scenario_data.accept_orientation ? VLC_SUCCESS : VLC_EGENERIC;
}

static void converter_orientation(filter_t *filter)
{
    assert(!scenario_data.accept_orientation);
    assert(filter->fmt_in.video.orientation == ORIENT_ROTATED_90);
    assert(filter->fmt_out.video.orientation == ORIENT_NORMAL);
    scenario_data.converter_opened = true;
}

static void display_prepare_orientation(vout_display_t *vd, picture_t *picture)
{
    if (!scenario_data.filter_requested)
    {
        scenario_data.filter_requested = true;
        vlc_object_t *vout = vlc_object_parent(vd);
        var_SetString(vout, "video-filter", scenario_data.real_transform
            ? "transform{type=90}" : "test_vout_mock");
        return;
    }
    if (scenario_data.format_updates == 0 ||
        atomic_load(&scenario_data.orientation_finished))
        return;
    video_orientation_t expected = scenario_data.accept_orientation && scenario_data.format_updates == 1
        ? ORIENT_ROTATED_90 : ORIENT_NORMAL;
    assert(vd->source->orientation == expected);
    /* A metadata-only filter leaves the original picture untouched. */
    assert(picture->format.orientation == ORIENT_NORMAL);
    if (scenario_data.accept_orientation && scenario_data.format_updates == 1)
    {
        var_SetString(vlc_object_parent(vd), "video-filter", "");
        return;
    }
    if (!scenario_data.accept_orientation)
        assert(scenario_data.converter_opened);
    atomic_store(&scenario_data.orientation_finished, true);
    vlc_sem_post(&scenario_data.wait_stop);
}

const char source_800_600[] = "mock://video_track_count=1;length=100000000000;video_width=800;video_height=600";
struct vout_scenario vout_scenarios[] =
{{
    .source = source_800_600,
    .decoder_setup = decoder_rgba_800_600,
    .decoder_decode = decoder_decode_change_chroma,
    .display_setup = display_800_600_fail_second_time,
}, {
    .source = source_800_600,
    .decoder_setup = decoder_rgba_800_600,
    .decoder_decode = decoder_decode_orientation,
    .display_setup = display_orientation_accept,
    .display_update_format = display_update_orientation,
    .display_prepare = display_prepare_orientation,
    .filter_setup = filter_orientation,
}, {
    .source = source_800_600,
    .decoder_setup = decoder_rgba_800_600,
    .decoder_decode = decoder_decode_orientation,
    .display_setup = display_orientation_reject,
    .display_update_format = display_update_orientation,
    .display_prepare = display_prepare_orientation,
    .filter_setup = filter_orientation,
    .converter_setup = converter_orientation,
}, {
    .source = source_800_600,
    .decoder_setup = decoder_context_rgba_800_600,
    .decoder_decode = decoder_decode_orientation,
    .display_setup = display_transform_context,
    .display_update_format = display_update_orientation,
    .display_prepare = display_prepare_orientation,
}};
size_t vout_scenarios_count = ARRAY_SIZE(vout_scenarios);

void vout_scenario_init(void)
{
    atomic_init(&scenario_data.orientation_finished, false);
    scenario_data.filter_requested = false;
    scenario_data.accept_orientation = false;
    scenario_data.format_updates = 0;
    scenario_data.real_transform = false;
    scenario_data.decoder_vctx = NULL;
    scenario_data.display_picture_count = 0;
    scenario_data.converter_opened = false;
    scenario_data.display_opened = false;
    scenario_data.test_finished = false;
    vlc_sem_init(&scenario_data.wait_stop, 0);
}

void vout_scenario_wait(struct vout_scenario *scenario)
{
    vlc_sem_wait(&scenario_data.wait_stop);
    if (scenario->converter_setup != NULL)
        assert(scenario_data.converter_opened);

    if (scenario->display_setup != NULL)
        assert(scenario_data.display_opened);
}
