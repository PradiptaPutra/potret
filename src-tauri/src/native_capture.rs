use block2::RcBlock;
use objc2::{runtime::AnyClass, sel};
use objc2_core_foundation::{CFDictionary, CFMutableData, CFNumber, CFString};
use objc2_core_graphics::{CGDisplayBounds, CGImage, CGMainDisplayID};
use objc2_foundation::NSError;
use objc2_image_io::{
    kCGImageDestinationImageMaxPixelSize, kCGImageDestinationLossyCompressionQuality,
    CGImageDestination,
};
use objc2_screen_capture_kit::SCScreenshotManager;
use std::sync::mpsc;
use std::time::{Duration, Instant};

pub struct NativeCapture {
    pub bytes: Vec<u8>,
    pub width: u32,
    pub height: u32,
    pub frame_ms: u128,
    pub encode_ms: u128,
}

pub struct NativePreview {
    pub bytes: Vec<u8>,
    pub width: u32,
    pub height: u32,
    pub frame_ms: u128,
    pub encode_ms: u128,
}

fn encode_image(
    image: &CGImage,
    type_identifier: &'static str,
    properties: Option<&CFDictionary>,
) -> Result<Vec<u8>, String> {
    let data = CFMutableData::new(None, 0)
        .ok_or_else(|| "ImageIO could not allocate image output".to_string())?;
    let image_type = CFString::from_static_str(type_identifier);
    let destination = unsafe { CGImageDestination::with_data(&data, &image_type, 1, None) }
        .ok_or_else(|| "ImageIO could not create an image destination".to_string())?;

    unsafe {
        destination.add_image(image, properties);
        if !destination.finalize() {
            return Err("ImageIO failed to finalize the image".to_string());
        }
    }
    Ok(data.to_vec())
}

fn encode_capture(
    image: &CGImage,
    frame_ms: u128,
    publish_preview: &dyn Fn(NativePreview) -> Result<(), String>,
) -> Result<NativeCapture, String> {
    let width = CGImage::width(Some(image));
    let height = CGImage::height(Some(image));
    let width = u32::try_from(width).map_err(|_| "Captured image is too wide".to_string())?;
    let height = u32::try_from(height).map_err(|_| "Captured image is too tall".to_string())?;

    let preview_start = Instant::now();
    let max_size = CFNumber::new_i32(640);
    let quality = CFNumber::new_f32(0.72);
    let properties = CFDictionary::from_slices(
        unsafe {
            &[
                kCGImageDestinationImageMaxPixelSize,
                kCGImageDestinationLossyCompressionQuality,
            ]
        },
        &[&*max_size, &*quality],
    );
    let preview_bytes = encode_image(image, "public.jpeg", Some(properties.as_ref()))?;
    let preview_encode_ms = preview_start.elapsed().as_millis();
    publish_preview(NativePreview {
        bytes: preview_bytes,
        width,
        height,
        frame_ms,
        encode_ms: preview_encode_ms,
    })?;

    let encode_start = Instant::now();
    let bytes = encode_image(image, "public.png", None)?;

    Ok(NativeCapture {
        bytes,
        width,
        height,
        frame_ms,
        encode_ms: encode_start.elapsed().as_millis(),
    })
}

pub fn capture_main_display_png<F>(publish_preview: F) -> Result<NativeCapture, String>
where
    F: Fn(NativePreview) -> Result<(), String> + Send + 'static,
{
    let screenshot_class = AnyClass::get(c"SCScreenshotManager")
        .ok_or_else(|| "SCScreenshotManager is unavailable".to_string())?;
    if !screenshot_class
        .metaclass()
        .responds_to(sel!(captureImageInRect:completionHandler:))
    {
        return Err("ScreenCaptureKit single-frame capture is unavailable".to_string());
    }

    let request_start = Instant::now();
    let display_bounds = CGDisplayBounds(CGMainDisplayID());
    let (sender, receiver) = mpsc::sync_channel(1);
    let completion = RcBlock::new(move |image: *mut CGImage, error: *mut NSError| {
        let result = if image.is_null() {
            let message = if error.is_null() {
                "ScreenCaptureKit returned no image"
            } else {
                "ScreenCaptureKit failed to capture the display"
            };
            Err(message.to_string())
        } else {
            let frame_ms = request_start.elapsed().as_millis();
            // The callback owns a valid image for its duration; ImageIO consumes it synchronously.
            encode_capture(unsafe { &*image }, frame_ms, &publish_preview)
        };
        let _ = sender.send(result);
    });

    unsafe {
        SCScreenshotManager::captureImageInRect_completionHandler(
            display_bounds,
            Some(&completion),
        );
    }

    receiver
        .recv_timeout(Duration::from_secs(3))
        .map_err(|_| "ScreenCaptureKit timed out".to_string())?
}
