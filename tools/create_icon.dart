import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:image/image.dart' as img;

void main() async {
  try {
    // Create a simple placeholder icon
    final image = img.Image(width: 1024, height: 1024);
    
    // Fill with background (dark theme)
    img.fill(image, color: img.ColorRgb8(13, 13, 13)); // #0D0D0D
    
    // Add yellow circle background
    final center = 512;
    final radius = 400;
    
    for (int y = 0; y < 1024; y++) {
      for (int x = 0; x < 1024; x++) {
        final dx = x - center;
        final dy = y - center;
        final distance = sqrt(dx * dx + dy * dy);
        if (distance <= radius) {
          // Create gradient effect
          final ratio = distance / radius;
          final yellow = img.ColorRgb8(255, 215, 0); // Gold color
          image.setPixel(x, y, img.ColorRgb8(
            (yellow.r * (1 - ratio * 0.5) + 13 * ratio * 0.5).round(),
            (yellow.g * (1 - ratio * 0.5) + 13 * ratio * 0.5).round(),
            (yellow.b * (1 - ratio * 0.5) + 13 * ratio * 0.5).round(),
          ));
        }
      }
    }
    
    // Add a simple graduation cap icon
    final capCenter = 512;
    final capSize = 300;
    
    // Draw graduation cap shape
    for (int y = capCenter - capSize~/2; y < capCenter + capSize~/2; y++) {
      for (int x = capCenter - capSize~/2; x < capCenter + capSize~/2; x++) {
        // Simple square cap
        if (y >= capCenter - capSize~/4 && y <= capCenter + capSize~/4 &&
            x >= capCenter - capSize~/2 && x <= capCenter + capSize~/2) {
          image.setPixel(x, y, img.ColorRgb8(255, 255, 255));
        }
        // Simple brim
        if (y >= capCenter + capSize~/4 - 20 && y <= capCenter + capSize~/4 &&
            x >= capCenter - capSize~/2 - 50 && x <= capCenter + capSize~/2 + 50) {
          image.setPixel(x, y, img.ColorRgb8(255, 255, 255));
        }
      }
    }
    
    // Save the image
    final outputBytes = Uint8List.fromList(img.encodePng(image));
    final outputFile = File('assets/icon/app_icon.png');
    await outputFile.writeAsBytes(outputBytes);
    
    print('✅ App icon created successfully at: ${outputFile.path}');
    print('📏 Final size: 1024x1024 pixels');
    print('🎨 Design: Gold background with graduation cap icon');
    
  } catch (e) {
    print('❌ Error creating icon: $e');
  }
}
