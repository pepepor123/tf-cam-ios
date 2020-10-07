//
//  ModelDataHandler.swift
//  tf-cam
//
//  Created by hrbysnk on 2020/10/06.
//

import UIKit
import Accelerate
import CoreImage
import TensorFlowLite

// Stores results for a particular frame that was successfully run through the `Interpreter`.
struct Result {
  let inferenceTime: Double
  let inferences: [Inference]
}

// Stores one formatted inference.
struct Inference {
  let confidence: Float
  let className: String
  let rect: CGRect
  let displayColor: UIColor
}

// Information about a model file or a labels file.
typealias FileInfo = (name: String, extension: String)

// Information about the MobileNet SSD model.
enum MobileNetSSD {
  static let modelInfo: FileInfo = (name: "detect", extension: "tflite")
  static let labelsInfo: FileInfo = (name: "labelmap", extension: "txt")
}

// This class handles all data preprocessing and makes calls to run inference on a given frame
// by invoking the `Interpreter`. It then formats the inferences obtained and returns the top N
// results for a successful inference.
class ModelDataHandler: NSObject {

  // MARK: - Internal properties
  // The current thread count used by the TensorFlow Lite Interpreter.
  let threadCount: Int
  let threadCountLimit = 10

  let threshold: Float = 0.5

  // MARK: Model parameters
  let batchSize = 1
  let inputChannels = 3
  let inputWidth = 300
  let inputHeight = 300

  // image mean and std for floating model.
  let imageMean: Float = 127.5
  let imageStd:  Float = 127.5

  // MARK: Private properties
  private var labels: [String] = []

  // TensorFlow Lite `Interpreter` object for performing inference on a given model.
  private var interpreter: Interpreter

  private let bgraPixel = (channels: 4, alphaComponent: 3, lastBgrComponent: 2)
  private let rgbPixelChannels = 3
  private let colorStrideValue = 10
  private let colors = [
    UIColor.red,
    UIColor(displayP3Red: 90.0/255.0, green: 200.0/255.0, blue: 250.0/255.0, alpha: 1.0),
    UIColor.green,
    UIColor.orange,
    UIColor.blue,
    UIColor.purple,
    UIColor.magenta,
    UIColor.yellow,
    UIColor.cyan,
    UIColor.brown
  ]

  // MARK: - Initialization

  // A failable initializer for `ModelDataHandler`. A new instance is created if the model file and
  // labels file are successfully loaded from the app's main bundle. Default `threadCount` is 1.
  init?(modelFileInfo: FileInfo, labelsFileInfo: FileInfo, threadCount: Int = 1) {
    let modelFilename = modelFileInfo.name

    // Constructs the path to the model file.
    guard let modelPath = Bundle.main.path(forResource: modelFilename, ofType: modelFileInfo.extension) else {
      print("Failed to load the model file with name: \(modelFilename).")
      return nil
    }

    // Specifies the options for the `Interpreter`.
    self.threadCount = threadCount
    var options = Interpreter.Options()
    options.threadCount = threadCount
    do {
      // Creates the `Interpreter`.
      interpreter = try Interpreter(modelPath: modelPath, options: options)
      // Allocates memory for the model's input `Tensor`s.
      try interpreter.allocateTensors()
    } catch let error {
      print("Failed to create the interpreter with error: \(error.localizedDescription)")
      return nil
    }

    super.init()

    // Loads classes listed in the labels file.
    loadLabels(fileInfo: labelsFileInfo)
  }

  // Runs inference on a given frame
  func runModel(onFrame pixelBuffer: CVPixelBuffer) -> Result? {
    let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
    let imageHeight = CVPixelBufferGetHeight(pixelBuffer)
    let sourcePixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
    assert(sourcePixelFormat == kCVPixelFormatType_32ARGB || sourcePixelFormat == kCVPixelFormatType_32BGRA || sourcePixelFormat == kCVPixelFormatType_32RGBA)

    let imageChannels = 4
    assert(imageChannels >= inputChannels)

    // Scales down the image to model dimensions.
    let scaledSize = CGSize(width: inputWidth, height: inputHeight)
    guard let scaledPixelBuffer = pixelBuffer.resized(to: scaledSize) else {
      return nil
    }

    let interval: TimeInterval
    let outputBoundingBoxes: Tensor
    let outputClasses: Tensor
    let outputScores: Tensor
    let outputCount: Tensor
    do {
      let inputTensor = try interpreter.input(at: 0)

      // Removes the alpha component from the image buffer to get RGB data.
      guard let rgbData = rgbDataFromBuffer(
        scaledPixelBuffer,
        byteCount: batchSize * inputWidth * inputHeight * inputChannels,
        isModelQuantized: inputTensor.dataType == .uInt8
      ) else {
        print("Failed to convert the image buffer to RGB data.")
        return nil
      }

      // Copies the RGB data to the input `Tensor`.
      try interpreter.copy(rgbData, toInputAt: 0)

      // Runs inference by invoking the `Interpreter`.
      let startDate = Date()
      try interpreter.invoke()
      interval = Date().timeIntervalSince(startDate) * 1000

      outputBoundingBoxes = try interpreter.output(at: 0)
      outputClasses = try interpreter.output(at: 1)
      outputScores = try interpreter.output(at: 2)
      outputCount = try interpreter.output(at: 3)
    } catch let error {
      print("Failed to invoke the interpreter with error: \(error.localizedDescription)")
      return nil
    }

    // Formats the results.
    let resultArray = formatResults(
      boundingBoxes: [Float](unsafeData: outputBoundingBoxes.data) ?? [],
      outputClasses: [Float](unsafeData: outputClasses.data) ?? [],
      outputScores: [Float](unsafeData: outputScores.data) ?? [],
      outputCount: Int(([Float](unsafeData: outputCount.data) ?? [0])[0]),
      width: CGFloat(imageWidth),
      height: CGFloat(imageHeight)
    )

    // Returns the inference time and inferences.
    let result = Result(inferenceTime: interval, inferences: resultArray)
    return result
  }

  // Filters out all the results with confidence score < threshold and returns the top N results sorted in descending order.
  func formatResults(boundingBoxes: [Float], outputClasses: [Float], outputScores: [Float], outputCount: Int, width: CGFloat, height: CGFloat) -> [Inference] {
    var resultArray: [Inference] = []
    if (outputCount == 0) {
      return resultArray
    }
    for i in 0...outputCount - 1 {

      let score = outputScores[i]

      // Filters results with confidence < threshold.
      guard score >= threshold else {
        continue
      }

      // Gets the output class name from the labels list.
      let outputClassIndex = Int(outputClasses[i])
      let outputClass = labels[outputClassIndex + 1]

      var rect: CGRect = CGRect.zero

      // Translates the detected bounding box to CGRect.
      rect.origin.y = CGFloat(boundingBoxes[4*i])
      rect.origin.x = CGFloat(boundingBoxes[4*i+1])
      rect.size.height = CGFloat(boundingBoxes[4*i+2]) - rect.origin.y
      rect.size.width = CGFloat(boundingBoxes[4*i+3]) - rect.origin.x

      // The detected corners are for model dimensions, so we scale the rect with respect to the actual image dimensions.
      let newRect = rect.applying(CGAffineTransform(scaleX: width, y: height))

      // Gets the color assigned for the class
      let colorToAssign = colorForClass(withIndex: outputClassIndex + 1)
      let inference = Inference(confidence: score, className: outputClass, rect: newRect, displayColor: colorToAssign)
      resultArray.append(inference)
    }

    // Sorts results in descending order of confidence.
    resultArray.sort { (first, second) -> Bool in
      return first.confidence > second.confidence
    }

    return resultArray
  }

  // Loads labels from the file and stores them in the `labels` property.
  private func loadLabels(fileInfo: FileInfo) {
    let filename = fileInfo.name
    let fileExtension = fileInfo.extension
    guard let fileURL = Bundle.main.url(forResource: filename, withExtension: fileExtension) else {
      fatalError("Labels file not found in bundle. Please add a labels file with name \(filename).\(fileExtension) and try again.")
    }
    do {
      let contents = try String(contentsOf: fileURL, encoding: .utf8)
      labels = contents.components(separatedBy: .newlines)
    } catch {
      fatalError("Labels file named \(filename).\(fileExtension) cannot be read. Please add a valid labels file and try again.")
    }
  }

  /// Returns RGB data representation of the given image buffer with the specified `byteCount`.
  ///
  /// - Parameters
  ///   - buffer: The BGRA pixel buffer to convert to RGB data.
  ///   - byteCount: The expected byte count for the RGB data: `batchSize * imageWidth * imageHeight * componentsCount`.
  ///   - isModelQuantized: Whether the model is quantized (i.e. fixed point values rather than floating point values).
  ///
  private func rgbDataFromBuffer(_ buffer: CVPixelBuffer, byteCount: Int, isModelQuantized: Bool) -> Data? {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer {
      CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
    }
    guard let sourceData = CVPixelBufferGetBaseAddress(buffer) else {
      return nil
    }

    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    let destinationChannelCount = 3
    let destinationBytesPerRow = destinationChannelCount * width

    var sourceBuffer = vImage_Buffer(data: sourceData, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: sourceBytesPerRow)

    guard let destinationData = malloc(height * destinationBytesPerRow) else {
      print("Error: out of memory")
      return nil
    }

    defer {
      free(destinationData)
    }

    var destinationBuffer = vImage_Buffer(data: destinationData, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: destinationBytesPerRow)

    if (CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA) {
      vImageConvert_BGRA8888toRGB888(&sourceBuffer, &destinationBuffer, UInt32(kvImageNoFlags))
    } else if (CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32ARGB) {
      vImageConvert_ARGB8888toRGB888(&sourceBuffer, &destinationBuffer, UInt32(kvImageNoFlags))
    }

    let byteData = Data(bytes: destinationBuffer.data, count: destinationBuffer.rowBytes * height)
    if isModelQuantized {
      return byteData
    }

    // Converts to floats if not quantized
    let bytes = Array<UInt8>(unsafeData: byteData)!
    var floats = [Float]()
    for i in 0..<bytes.count {
      floats.append((Float(bytes[i]) - imageMean) / imageStd)
    }
    return Data(copyingBufferOf: floats)
  }

  // This assigns a color for a particular class.
  private func colorForClass(withIndex index: Int) -> UIColor {
    let baseColor = colors[index % colors.count]
    var colorToAssign = baseColor
    let percentage = CGFloat((colorStrideValue / 2 - index / colors.count) * colorStrideValue)

    if let modifiedColor = baseColor.getModified(byPercentage: percentage) {
      colorToAssign = modifiedColor
    }

    return colorToAssign
  }
}

// MARK: - Extensions

extension CVPixelBuffer {

  // Returns scaled pixel buffer.
  func resized(to size: CGSize) -> CVPixelBuffer? {

    let imageWidth = CVPixelBufferGetWidth(self)
    let imageHeight = CVPixelBufferGetHeight(self)

    let pixelBufferType = CVPixelBufferGetPixelFormatType(self)

    assert(pixelBufferType == kCVPixelFormatType_32BGRA || pixelBufferType == kCVPixelFormatType_32ARGB)

    let inputImageRowBytes = CVPixelBufferGetBytesPerRow(self)
    let imageChannels = 4

    CVPixelBufferLockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))

    guard let inputBaseAddress = CVPixelBufferGetBaseAddress(self) else {
      return nil
    }

    // Gets vImage Buffer from input image.
    var inputVImageBuffer = vImage_Buffer(data: inputBaseAddress, height: UInt(imageHeight), width: UInt(imageWidth), rowBytes: inputImageRowBytes)

    let scaledImageRowBytes = Int(size.width) * imageChannels
    guard let scaledImageBytes = malloc(Int(size.height) * scaledImageRowBytes) else {
      return nil
    }

    // Allocates a vImage buffer for scaled image.
    var scaledVImageBuffer = vImage_Buffer(data: scaledImageBytes, height: UInt(size.height), width: UInt(size.width), rowBytes: scaledImageRowBytes)

    // Performs the scale operation on input image buffer and stores it in scaled image buffer.
    let scaleError = vImageScale_ARGB8888(&inputVImageBuffer, &scaledVImageBuffer, nil, vImage_Flags(0))

    CVPixelBufferUnlockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))

    guard scaleError == kvImageNoError else {
      return nil
    }

    let releaseCallBack: CVPixelBufferReleaseBytesCallback = { mutablePointer, pointer in

      if let pointer = pointer {
        free(UnsafeMutableRawPointer(mutating: pointer))
      }
    }

    var scaledPixelBuffer: CVPixelBuffer?

    // Converts the scaled vImage buffer to CVPixelBuffer.
    let conversionStatus = CVPixelBufferCreateWithBytes(nil, Int(size.width), Int(size.height), pixelBufferType, scaledImageBytes, scaledImageRowBytes, releaseCallBack, nil, nil, &scaledPixelBuffer)

    guard conversionStatus == kCVReturnSuccess else {
      free(scaledImageBytes)
      return nil
    }

    return scaledPixelBuffer
  }

}

extension UIColor {
  /**
   This method returns a color modified by percentage value.
   */
  func getModified(byPercentage percent: CGFloat) -> UIColor? {
    var red: CGFloat = 0.0
    var green: CGFloat = 0.0
    var blue: CGFloat = 0.0
    var alpha: CGFloat = 0.0

    guard self.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
      return nil
    }

    let colorToReturn = UIColor(displayP3Red: min(red + percent / 100.0, 1.0), green: min(green + percent / 100.0, 1.0), blue: min(blue + percent / 100.0, 1.0), alpha: 1.0)

    return colorToReturn
  }
}

extension Data {
  /// Creates a new buffer by copying the buffer pointer of the given array.
  /// - Parameter array: An array with elements of type `T`.
  ///
  init<T>(copyingBufferOf array: [T]) {
    self = array.withUnsafeBufferPointer(Data.init)
  }
}

extension Array {
  /// Creates a new array from the given unsafe data.
  /// - Parameter unsafeData: The data containing the bytes to turn into an array.
  ///
  init?(unsafeData: Data) {
    guard unsafeData.count % MemoryLayout<Element>.stride == 0 else { return nil }
    #if swift(>=5.0)
    self = unsafeData.withUnsafeBytes { .init($0.bindMemory(to: Element.self)) }
    #else
    self = unsafeData.withUnsafeBytes {
      .init(UnsafeBufferPointer<Element>(
        start: $0,
        count: unsafeData.count / MemoryLayout<Element>.stride
      ))
    }
    #endif  // swift(>=5.0)
  }
}
