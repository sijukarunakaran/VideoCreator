//
//  VideoCreation.swift
//  VideoCreation
//
//  Created by Siju Karunakaran on 29/07/23.
//

import UIKit
import AVFoundation

extension UIColor {
    static var random: UIColor {
        let redValue = CGFloat(drand48())
        let greenValue = CGFloat(drand48())
        let blueValue = CGFloat(drand48())
        
        let randomColor = UIColor(red: redValue, green: greenValue, blue: blueValue, alpha: 1.0)
        
        return randomColor
    }
}

enum VideoResolution: Int {
    case SD = 480
    case HD = 720
    case FullHD = 1080
    
    var aspectRatio: Double {
        switch self {
        case .SD: return 4/3
        case .HD, .FullHD: return 16/9
        }
    }
    
    var width: Int {
        let height = Double(self.rawValue)
        return Int(aspectRatio * height)
    }
    
    var height: Int {
        self.rawValue
    }
    
    var size: CGSize {
        .init(width: width, height: height)
    }
}
protocol VideoRendering {
    
}


class VideoRenderer {
    static let shared = VideoRenderer()
    private let framesPerSecond: Int32 = 30
    
    func renderVideo(withText text: String, duration: TimeInterval, resolution: VideoResolution = .HD, completion: @escaping (URL?) -> Void) {
        let outputSize = resolution.size
        
        let videoURL = createTempVideoURL()
        
        guard let videoWriter = try? AVAssetWriter(outputURL: videoURL, fileType: .mp4) else {
            completion(nil)
            return
        }
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height
        ]
        
        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: outputSize.width,
            kCVPixelBufferHeightKey as String: outputSize.height
        ]
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )
        
        videoWriterInput.expectsMediaDataInRealTime = true
        videoWriter.add(videoWriterInput)
        
        videoWriter.startWriting()
        videoWriter.startSession(atSourceTime: .zero)
        
        let processingQueue = DispatchQueue(label: "VideoProcessingQueue", qos: .background)
        
        videoWriterInput.requestMediaDataWhenReady(on: processingQueue) {
            let textDuration = CMTime(seconds: duration, preferredTimescale: self.framesPerSecond)
            var frameCount: Int64 = 0
            
            while videoWriterInput.isReadyForMoreMediaData {
                let frameTime = CMTime(value: frameCount, timescale: self.framesPerSecond)
                
                if frameTime >= textDuration {
                    videoWriterInput.markAsFinished()
                    videoWriter.finishWriting { [weak self] in
                        print("Adding Audio")
                        self?.addAudio(to: videoURL, completion: completion)
                    }
                    break
                }
                print("\(frameTime) >= \(textDuration)")
                if pixelBufferAdaptor.assetWriterInput.isReadyForMoreMediaData {
                    let presentationTime = frameCount == 0 ? .zero : CMTime(seconds: Double(frameCount) / Double(self.framesPerSecond), preferredTimescale: self.framesPerSecond)
                    var pixelBuffer: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferAdaptor.pixelBufferPool!, &pixelBuffer)
                    
                    if let pixelBuffer = pixelBuffer {
                        self.renderFrame(at: presentationTime, withText: text, on: pixelBuffer, in: outputSize)
                        if !pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                            print("Failed to append pixel buffer at time: \(presentationTime)")
                        }
                        frameCount += 1
                    }
                }
            }
        }
    }
    
    private func createTempVideoURL() -> URL {
        let tempDirectoryURL = FileManager.default.temporaryDirectory
        let videoFileName = "renderedVideo.mp4"
        let result = tempDirectoryURL.appendingPathComponent(videoFileName)
        deleteTempVideo(result)
        return result
    }
    
    private func createTempFullVideoURL() -> URL {
        let tempDirectoryURL = FileManager.default.temporaryDirectory
        let videoFileName = "final.mp4"
        let result = tempDirectoryURL.appendingPathComponent(videoFileName)
        deleteTempVideo(result)
        return result
    }
    
    private func deleteTempVideo(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
    
    
    private func renderFrame(at time: CMTime, withText text: String, on pixelBuffer: CVPixelBuffer, in outputSize: CGSize) {
        let renderer = UIGraphicsImageRenderer(size: outputSize)
        
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 50),
                .paragraphStyle: paragraphStyle,
                .foregroundColor: UIColor.black
            ]
            
            let attributedString = NSAttributedString(string: text, attributes: attributes)
            
            let textRect = CGRect(x: 0, y: outputSize.height / 2 - 50, width: outputSize.width, height: 100)
            attributedString.draw(in: textRect)
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(outputSize.width),
            height: Int(outputSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )
        
        let imageRect = CGRect(origin: .zero, size: outputSize)
        context?.clear(imageRect)
        context?.draw(image.cgImage!, in: imageRect)
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
    }
    
    func addAudio(to videoURL: URL, completion: @escaping (URL?) -> Void) {
        do {
            let composition = AVMutableComposition()
            
            let videoAsset = AVURLAsset(url: videoURL)
            let videoAssetTrack = videoAsset.tracks(withMediaType: .video).first!
            
            let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            try compositionVideoTrack?.insertTimeRange(CMTimeRange(start: CMTime.zero, duration: videoAsset.duration), of: videoAssetTrack, at: CMTime.zero)
                    
            let audioAsset = AVURLAsset(url: Bundle.main.url(forResource: "audio", withExtension: "wav")!)

            let audioAssetTrack = audioAsset.tracks(withMediaType: .audio).first!
            
            let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try compositionAudioTrack?.insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: audioAsset.duration), of: audioAssetTrack, at: .zero)

            var assetExport = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetMediumQuality)

            assetExport?.outputFileType = AVFileType.mp4
            let finalURL = createTempFullVideoURL()
            assetExport?.outputURL = finalURL
            print("Export starts")
            assetExport?.exportAsynchronously(completionHandler: {
                switch (assetExport!.status)
                {
                case .cancelled:
                    print(assetExport?.error?.localizedDescription)
                    break
                case .completed:
                    print("Audio added")
                    completion(finalURL)
                case .exporting:
                    break
                case .failed:
                    print(assetExport?.error?.localizedDescription)
                    break
                case .unknown:
                    break
                case .waiting:
                    break
                @unknown default:
                    break
                }
            })
        }
        catch {
            print(error)
            completion(nil)
        }
    }
}
