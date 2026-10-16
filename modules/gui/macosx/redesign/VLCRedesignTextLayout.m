/*****************************************************************************
 * VLCRedesignTextLayout.m: Text alignment for redesigned native controls
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import "VLCRedesignTextLayout.h"
#import <CoreText/CoreText.h>

void VLCDrawAlignedText(NSAttributedString *text, NSRect bounds, BOOL flipped, NSTextAlignment alignment)
{
    if (!text.length || NSIsEmptyRect(bounds))
        return;

    NSMutableAttributedString *content = text.mutableCopy;
    NSMutableParagraphStyle *paragraph = [[content attribute:NSParagraphStyleAttributeName atIndex:0
                                              effectiveRange:NULL] mutableCopy] ?: [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = alignment;
    [content addAttribute:NSParagraphStyleAttributeName value:paragraph range:NSMakeRange(0, content.length)];
    if (paragraph.lineBreakMode == NSLineBreakByTruncatingHead ||
        paragraph.lineBreakMode == NSLineBreakByTruncatingMiddle ||
        paragraph.lineBreakMode == NSLineBreakByTruncatingTail) {
        CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)content);
        NSAttributedString *ellipsis = [[NSAttributedString alloc] initWithString:@"…" attributes:[content attributesAtIndex:0 effectiveRange:NULL]];
        CTLineRef token = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)ellipsis);
        CTLineTruncationType type = paragraph.lineBreakMode == NSLineBreakByTruncatingMiddle ? kCTLineTruncationMiddle :
                                   paragraph.lineBreakMode == NSLineBreakByTruncatingHead ? kCTLineTruncationStart : kCTLineTruncationEnd;
        CTLineRef truncated = CTLineCreateTruncatedLine(line, NSWidth(bounds), type, token);
        CTLineRef visible = truncated ?: line;
        CGRect ink = CTLineGetBoundsWithOptions(visible, kCTLineBoundsUseGlyphPathBounds);
        CGFloat x = NSMinX(bounds) - CGRectGetMinX(ink);
        if (alignment == NSTextAlignmentCenter) x = NSMidX(bounds) - CGRectGetMidX(ink);
        else if (alignment == NSTextAlignmentRight) x = NSMaxX(bounds) - CGRectGetMaxX(ink);
        CGContextRef context = NSGraphicsContext.currentContext.CGContext;
        CGContextSaveGState(context);
        CGContextClipToRect(context, bounds);
        if (flipped) {
            CGContextTranslateCTM(context, 0, NSMinY(bounds) + NSMaxY(bounds));
            CGContextScaleCTM(context, 1, -1);
        }
        CGContextSetTextMatrix(context, CGAffineTransformIdentity);
        CGContextSetTextPosition(context, x, NSMidY(bounds) - CGRectGetMidY(ink));
        CTLineDraw(visible, context);
        CGContextRestoreGState(context);
        if (truncated) CFRelease(truncated);
        CFRelease(token);
        CFRelease(line);
        return;
    }
    NSFont *font = [content attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] ?:
                   [NSFont systemFontOfSize:NSFont.systemFontSize];
    CTFramesetterRef setter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)content);
    CGSize size = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRangeMake(0, content.length), NULL,
                                                              CGSizeMake(NSWidth(bounds), CGFLOAT_MAX), NULL);
    CGFloat extraLine = ceil(font.ascender - font.descender + font.leading);
    CGFloat layoutHeight = MAX(NSHeight(bounds), ceil(size.height) + extraLine);
    CGPathRef path = CGPathCreateWithRect(CGRectMake(0, 0, NSWidth(bounds), layoutHeight), NULL);
    CTFrameRef frame = CTFramesetterCreateFrame(setter, CFRangeMake(0, content.length), path, NULL);
    CFArrayRef lines = CTFrameGetLines(frame);
    CFIndex count = CFArrayGetCount(lines);
    CGPoint *origins = calloc(count, sizeof(*origins));
    if (!origins) {
        CFRelease(frame);
        CGPathRelease(path);
        CFRelease(setter);
        return;
    }
    CTFrameGetLineOrigins(frame, CFRangeMake(0, count), origins);
    CGRect ink = CGRectNull;
    for (CFIndex i = 0; i < count; i++) {
        CTLineRef line = CFArrayGetValueAtIndex(lines, i);
        if (CTLineGetGlyphCount(line) == 0)
            continue;
        CGRect lineInk = CTLineGetBoundsWithOptions(line, kCTLineBoundsUseGlyphPathBounds);
        if (!CGRectIsEmpty(lineInk) && !CGRectIsNull(lineInk))
            ink = CGRectUnion(ink, CGRectOffset(lineInk, origins[i].x, origins[i].y));
    }
    free(origins);

    if (!CGRectIsNull(ink) && !CGRectIsEmpty(ink)) {
        CGFloat x = NSMinX(bounds) - CGRectGetMinX(ink);
        if (alignment == NSTextAlignmentCenter)
            x = NSMidX(bounds) - CGRectGetMidX(ink);
        else if (alignment == NSTextAlignmentRight)
            x = NSMaxX(bounds) - CGRectGetMaxX(ink);
        CGContextRef context = NSGraphicsContext.currentContext.CGContext;
        CGContextSaveGState(context);
        CGContextClipToRect(context, bounds);
        if (flipped) {
            CGContextTranslateCTM(context, 0, NSMinY(bounds) + NSMaxY(bounds));
            CGContextScaleCTM(context, 1, -1);
        }
        CGContextSetTextMatrix(context, CGAffineTransformIdentity);
        CGContextTranslateCTM(context, x, NSMidY(bounds) - CGRectGetMidY(ink));
        CTFrameDraw(frame, context);
        CGContextRestoreGState(context);
    }
    CFRelease(frame);
    CGPathRelease(path);
    CFRelease(setter);
}

@implementation VLCRedesignAlignedLabel
- (NSEdgeInsets)alignmentRectInsets
{
    /* Text is drawn in our bounds, without NSTextFieldCell's native padding. */
    return NSEdgeInsetsMake(0, 0, 0, 0);
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSMutableAttributedString *text = self.attributedStringValue.mutableCopy;
    NSRange range = NSMakeRange(0, text.length);
    [text addAttribute:NSFontAttributeName value:self.font range:range];
    [text addAttribute:NSForegroundColorAttributeName value:self.textColor range:range];
    if (self.maximumNumberOfLines == 1) {
        NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
        paragraph.lineBreakMode = self.lineBreakMode;
        [text addAttribute:NSParagraphStyleAttributeName value:paragraph range:range];
    }
    VLCDrawAlignedText(text, self.bounds, self.flipped, self.alignment);
}
@end

@implementation VLCRedesignAlignedTextFieldCell
- (NSRect)drawingRectForBounds:(NSRect)bounds
{
    NSRect rect = [super drawingRectForBounds:bounds];
    CGFloat lineHeight = ceil(self.font.ascender - self.font.descender);
    if (NSHeight(rect) <= lineHeight)
        return rect;

    NSString *text = self.stringValue.length ? self.stringValue : self.placeholderString;
    NSAttributedString *title = [[NSAttributedString alloc] initWithString:text ?: @""
        attributes:@{NSFontAttributeName:self.font}];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)title);
    CGFloat inkMidY = CGRectGetMidY(CTLineGetBoundsWithOptions(line, kCTLineBoundsUseGlyphPathBounds));
    CFRelease(line);
    /* The field editor adds descender padding below the visible glyphs. */
    CGFloat top = (NSHeight(rect) / 2) + inkMidY - ceil(self.font.ascender) + self.font.descender / 2;
    rect.origin.y += self.controlView.flipped ? top : NSHeight(rect) - top - lineHeight;
    rect.size.height = lineHeight;
    return rect;
}

- (void)selectWithFrame:(NSRect)rect inView:(NSView *)view editor:(NSText *)editor
              delegate:(id)delegate start:(NSInteger)start length:(NSInteger)length
{
    [super selectWithFrame:[self drawingRectForBounds:rect] inView:view editor:editor
                  delegate:delegate start:start length:length];
}

- (void)editWithFrame:(NSRect)rect inView:(NSView *)view editor:(NSText *)editor
            delegate:(id)delegate event:(NSEvent *)event
{
    [super editWithFrame:[self drawingRectForBounds:rect] inView:view editor:editor
                delegate:delegate event:event];
}
@end
