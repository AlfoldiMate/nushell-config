// rasterize.js — an SVG to a PNG with a real alpha channel, on a stock Mac
//
//   osascript -l JavaScript rasterize.js <in.svg> <out.png> [pixels]
//
// `theme use` renders themes/icon.svg through this. It used to go through
// `qlmanage -t`, the QuickLook thumbnailer, which composites every SVG onto an
// opaque white square: the padding around the rounded tile came out white, and
// so did the corners, in the Dock and the app switcher (found on 2026-09-19,
// after a light theme made the white obvious). NSImage has read SVG since
// macOS 11, and drawing it into an NSBitmapImageRep created with alpha leaves
// every pixel the SVG does not paint at 0,0,0,0 — 380k of the 1024² pixels for
// the icon. The rep is tagged sRGB so #282c34 lands as 40,44,52 exactly; the
// calibrated (generic RGB) space the constructor defaults to shifted it to
// 30,33,39. JXA is used because it is the one AppKit host every Mac ships
// with — no Xcode, no swift, no Python imaging. 100 ms.
ObjC.import('AppKit');
function run(argv) {
  var svg = argv[0], png = argv[1], px = parseInt(argv[2] || "1024", 10);
  var img = $.NSImage.alloc.initWithContentsOfFile(svg);
  if (img.isNil() || !img.isValid) { return "could not read " + svg; }
  var rep = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
    null, px, px, 8, 4, true, false, $.NSDeviceRGBColorSpace, 0, 0
  ).bitmapImageRepByRetaggingWithColorSpace($.NSColorSpace.sRGBColorSpace);
  $.NSGraphicsContext.saveGraphicsState;
  $.NSGraphicsContext.setCurrentContext($.NSGraphicsContext.graphicsContextWithBitmapImageRep(rep));
  img.drawInRectFromRectOperationFraction($.NSMakeRect(0, 0, px, px), $.NSZeroRect, $.NSCompositingOperationSourceOver, 1.0);
  $.NSGraphicsContext.restoreGraphicsState;
  var data = rep.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $());
  return data.writeToFileAtomically(png, true) ? "ok" : "could not write " + png;
}
