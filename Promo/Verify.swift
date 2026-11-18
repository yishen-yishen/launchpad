import Foundation
@preconcurrency import AVFoundation
import ImageIO
import UniformTypeIdentifiers

struct CheckError: Error { let message:String }
@main struct Verify {
    static func main() async throws {
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let url=root.appendingPathComponent("media/LaunchDock-Promo-1080p.mp4")
        let dir=root.appendingPathComponent("media/launchdock-promo/qa")
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let asset=AVURLAsset(url:url)
        let duration=try await asset.load(.duration).seconds
        guard let video=try await asset.loadTracks(withMediaType:.video).first,let audio=try await asset.loadTracks(withMediaType:.audio).first else {throw CheckError(message:"Missing video/audio")}
        let size=try await video.load(.naturalSize),fps=try await video.load(.nominalFrameRate)
        guard size.width==1920,size.height==1080,abs(duration-28)<0.1,abs(fps-30)<0.01 else{throw CheckError(message:"Unexpected dimensions or timing")}
        let generator=AVAssetImageGenerator(asset:asset);generator.appliesPreferredTrackTransform=true
        generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero
        for seconds in [1.6,5.5,10.5,12.5,15.5,16.5,19.5,25.0] {
            let result=try await generator.image(at:CMTime(seconds:seconds,preferredTimescale:600))
            let target=dir.appendingPathComponent("frame-\(seconds).png")
            let dest=CGImageDestinationCreateWithURL(target as CFURL,UTType.png.identifier as CFString,1,nil)!
            CGImageDestinationAddImage(dest,result.image,nil)
            guard CGImageDestinationFinalize(dest) else{throw CheckError(message:"PNG failed")}
        }
        let reader=try AVAssetReader(asset:asset)
        let output=AVAssetReaderTrackOutput(track:video,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
        reader.add(output);reader.startReading();var frames=0
        while let sample=output.copyNextSampleBuffer(){frames += 1;CMSampleBufferInvalidate(sample)}
        guard reader.status == .completed,frames==840 else{throw CheckError(message:"Video decode incomplete: \(frames)")}
        let audioReader=try AVAssetReader(asset:asset)
        let audioOutput=AVAssetReaderTrackOutput(track:audio,outputSettings:[AVFormatIDKey:kAudioFormatLinearPCM,AVLinearPCMIsFloatKey:true,AVLinearPCMBitDepthKey:32,AVLinearPCMIsNonInterleaved:false])
        audioReader.add(audioOutput);audioReader.startReading()
        var sum=0.0,peak:Float=0,count=0
        while let sample=audioOutput.copyNextSampleBuffer(){
            if let block=CMSampleBufferGetDataBuffer(sample){
                let length=CMBlockBufferGetDataLength(block)
                var values=[Float](repeating:0,count:length/4)
                let copied=values.withUnsafeMutableBytes{CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:length,destination:$0.baseAddress!)}
                guard copied==kCMBlockBufferNoErr else{throw CheckError(message:"Audio bytes")}
                for value in values {peak=max(peak,abs(value));sum += Double(value*value)}
                count += values.count
            }
        }
        let rms=sqrt(sum/Double(max(1,count)))
        guard audioReader.status == .completed,count>0,rms>0.001,peak<0.95 else{throw CheckError(message:"Audio decode/level failed")}
        let report:[String:Any]=["file":url.lastPathComponent,"durationSeconds":duration,"width":Int(size.width),"height":Int(size.height),"fps":fps,"decodedVideoFrames":frames,"decodedAudioSamples":count,"audioPeak":peak,"audioRMS":rms,"videoDecode":"complete","audioDecode":"complete","checkedFrameSeconds":[1.6,5.5,10.5,12.5,15.5,16.5,19.5,25.0]]
        let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:dir.appendingPathComponent("verification.json"));print(String(decoding:data,as:UTF8.self))
    }
}
