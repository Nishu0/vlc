/*****************************************************************************
 * freetype.c: live text renderer typography regressions
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "../../libvlc/test.h"
#include <vlc_filter.h>
#include <vlc_modules.h>
#include <vlc_subpicture.h>
#include <vlc_text_style.h>
#include "../lib/libvlc_internal.h"

#ifdef _WIN32
# define TEST_FONT "Arial"
# define TEST_MONOFONT "Courier New"
#else
# define TEST_FONT "sans-serif"
# define TEST_MONOFONT "monospace"
#endif

static subpicture_region_t *render_flags(filter_t *filter, bool styled, int flags)
{
    subpicture_region_t *text = subpicture_region_NewText();
    assert(text);
    text->p_text = text_segment_New("iiii WWWW live subtitle text");
    assert(text->p_text);
    if (styled)
    {
        text->p_text->style = text_style_Create(STYLE_NO_DEFAULTS);
        assert(text->p_text->style);
        text->p_text->style->i_font_color = 0xFF0000;
        text->p_text->style->i_features = STYLE_HAS_FONT_COLOR;
    }
    text->i_x = text->i_y = 0;
    text->text_flags = flags;
    const vlc_fourcc_t chromas[] = { VLC_CODEC_RGBA, 0 };
    subpicture_region_t *result = filter->ops->render(filter, text, chromas);
    subpicture_region_Delete(text);
    assert(result && result->p_picture);
    assert(result->p_picture->format.i_chroma == VLC_CODEC_RGBA);
    return result;
}

static subpicture_region_t *render(filter_t *filter, bool styled)
{
    return render_flags(filter, styled, 0);
}

static unsigned colored_pixels(const subpicture_region_t *region, unsigned channel)
{
    const picture_t *picture = region->p_picture;
    const plane_t *plane = &picture->p[0];
    unsigned count = 0;
    for (unsigned y = 0; y < picture->format.i_visible_height; y++)
    {
        const uint8_t *row = plane->p_pixels + y * plane->i_pitch;
        for (unsigned x = 0; x < picture->format.i_visible_width; x++)
        {
            const uint8_t *pixel = row + 4 * x;
            if (pixel[3] > 128 && pixel[channel] > 128 &&
                pixel[channel] > pixel[(channel + 1) % 3] + 50 &&
                pixel[channel] > pixel[(channel + 2) % 3] + 50)
                count++;
        }
    }
    return count;
}

int main(void)
{
    const char *options[] = { "--ignore-config", "--quiet", "--no-media-library" };
    libvlc_instance_t *vlc = libvlc_new(ARRAY_SIZE(options), options);
    assert(vlc);
    filter_t *filter = vlc_object_create(vlc->p_libvlc_int, sizeof(*filter));
    assert(filter);
    es_format_Init(&filter->fmt_in, VIDEO_ES, 0);
    es_format_Init(&filter->fmt_out, VIDEO_ES, 0);
    filter->fmt_out.video.i_width = filter->fmt_out.video.i_visible_width = 1280;
    filter->fmt_out.video.i_height = filter->fmt_out.video.i_visible_height = 720;
    var_Create(filter, "sub-text-scale", VLC_VAR_INTEGER);
    var_SetInteger(filter, "sub-text-scale", 100);
    var_Create(filter, "freetype-font-size", VLC_VAR_INTEGER);
    var_Create(filter, "freetype-override-styles", VLC_VAR_BOOL);
    var_Create(filter, "freetype-font", VLC_VAR_STRING);
    var_SetString(filter, "freetype-font", TEST_FONT);
    var_Create(filter, "freetype-color", VLC_VAR_INTEGER);
    var_SetInteger(filter, "freetype-color", 0x00FF00);
    filter->p_module = vlc_filter_LoadModule(filter, "text renderer", "freetype", true);
    assert(filter->p_module && filter->ops && filter->ops->render);

    subpicture_region_t *relative = render(filter, false);
    var_SetInteger(filter, "sub-text-scale", 150);
    subpicture_region_t *larger = render(filter, false);
    assert(larger->p_picture->format.i_visible_height > relative->p_picture->format.i_visible_height);
    fprintf(stderr, "Relative scaling remains live: PASS\n");

    var_SetInteger(filter, "freetype-font-size", 24);
    subpicture_region_t *small = render(filter, false);
    var_SetInteger(filter, "freetype-font-size", 48);
    subpicture_region_t *large = render(filter, false);
    fprintf(stderr, "Absolute sizes render heights %u and %u\n",
            small->p_picture->format.i_visible_height, large->p_picture->format.i_visible_height);
    assert(large->p_picture->format.i_visible_height > small->p_picture->format.i_visible_height * 1.4);
    fprintf(stderr, "Exact pixel sizes update without reopening the renderer: PASS\n");
    var_SetInteger(filter, "sub-text-scale", 300);
    subpicture_region_t *same = render(filter, false);
    assert(same->p_picture->format.i_visible_height == large->p_picture->format.i_visible_height);
    fprintf(stderr, "Pixel sizing is independent of the retained relative scale: PASS\n");
#if defined(__APPLE__) || defined(_WIN32) || defined(__ANDROID__) || defined(HAVE_FONTCONFIG)
    var_SetString(filter, "freetype-font", TEST_MONOFONT);
    subpicture_region_t *mono = render(filter, false);
    assert(mono->p_picture->format.i_visible_width != same->p_picture->format.i_visible_width);
    fprintf(stderr, "Changing font family refreshes the selected face: PASS\n");
    subpicture_region_Delete(mono);
#endif
    subpicture_region_t *styled = render(filter, true);
    assert(colored_pixels(styled, 0) > 0 && colored_pixels(styled, 1) == 0);
    var_SetBool(filter, "freetype-override-styles", true);
    subpicture_region_t *overridden = render(filter, true);
    assert(colored_pixels(overridden, 1) > 0 && colored_pixels(overridden, 0) == 0);
    fprintf(stderr, "Embedded color is honored or overridden according to the live setting: PASS\n");
    var_SetBool(filter, "freetype-override-styles", false);
    subpicture_region_t *restored = render(filter, true);
    assert(colored_pixels(restored, 0) > 0 && colored_pixels(restored, 1) == 0);
    fprintf(stderr, "Disabling the override restores embedded formatting: PASS\n");

    var_SetString(filter, "freetype-font", TEST_FONT);
    var_SetInteger(filter, "freetype-font-size", 0);
    var_SetInteger(filter, "sub-text-scale", 100);
    subpicture_region_t *relative_again = render(filter, false);
    assert(relative_again->p_picture->format.i_visible_height == relative->p_picture->format.i_visible_height);
    fprintf(stderr, "Returning to relative sizing restores the original size: PASS\n");
    var_SetInteger(filter, "freetype-font-size", 96);
    var_SetBool(filter, "freetype-override-styles", true);
    subpicture_region_t *grid = render_flags(filter, true, VLC_SUBPIC_TEXT_FLAG_GRID_MODE);
    assert(colored_pixels(grid, 0) > 0 && colored_pixels(grid, 1) == 0);
    fprintf(stderr, "Grid captions retain embedded formatting: PASS\n");

    subpicture_region_t *regions[] = { relative, larger, small, large, same, styled,
                                     overridden, restored, relative_again, grid };
    for (size_t i = 0; i < ARRAY_SIZE(regions); i++)
        subpicture_region_Delete(regions[i]);
    vlc_filter_Delete(filter);
    libvlc_release(vlc);
    return 0;
}
