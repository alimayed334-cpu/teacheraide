import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

void main() async {
  try {
    // Load the uploaded image
    final imageBytes = await rootBundle.load('assets/temp/profile_image.jpg');
    final originalImage = img.decodeImage(imageBytes.buffer.asUint8List());
    
    if (originalImage == null) {
      print('Failed to decode image');
      return;
    }
    
    // Get the original dimensions
    final originalWidth = originalImage.width;
    final originalHeight = originalImage.height;
    
    print('Original image size: ${originalWidth}x${originalHeight}');
    
    // Calculate the crop dimensions to make it square
    final cropSize = originalWidth < originalHeight ? originalWidth : originalHeight;
    final cropX = (originalWidth - cropSize) ~/ 2;
    final cropY = (originalHeight - cropSize) ~/ 2;
    
    // Crop the image to make it square
    final croppedImage = img.copyCrop(
      originalImage,
      x: cropX,
      y: cropY,
      width: cropSize,
      height: cropSize,
    );
    
    // Resize to 1024x1024
    final resizedImage = img.copyResize(
      croppedImage,
      width: 1024,
      height: 1024,
      interpolation: img.Interpolation.cubic,
    );
    
    // Save the processed image
    final outputBytes = Uint8List.fromList(img.encodePng(resizedImage));
    final outputFile = File('assets/icon/app_icon.png');
    await outputFile.writeAsBytes(outputBytes);
    
    print('✅ App icon created successfully at: ${outputFile.path}');
    print('📏 Final size: 1024x1024 pixels');
    
  } catch (e) {
    print('❌ Error processing image: $e');
  }
}
