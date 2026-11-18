import AppKit
@preconcurrency import AVFoundation
import CoreText
import ImageIO
import UniformTypeIdentifiers
import AudioToolbox

let width = 1920
let height = 1080
let fps = 30
let duration = 28.0
struct RenderFailure: Error, CustomStringConvertible { let description:String; init(_ description:String){self.description=description} }
func smooth(_ x: Double) -> Double { let t = min(1,max(0,x)); return t*t*(3-2*t) }
func color(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat,_ a:CGFloat=1) -> CGColor { CGColor(colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!,components:[r,g,b,a])! }
func text(_ c: CGContext,_ string:String,x:CGFloat,y:CGFloat,size:CGFloat,color value:CGColor = color(0.96,0.96,1),weight:String="Regular",center:Bool=false) {
    let font = CTFontCreateWithName("PingFangSC-\(weight)" as CFString,size,nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string:string,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font,NSAttributedString.Key(kCTForegroundColorAttributeName as String):value]))
    let measured = CTLineGetTypographicBounds(line,nil,nil,nil)
    c.saveGState();c.translateBy(x:x-(center ? measured/2:0),y:y+size);c.scaleBy(x:1,y:-1);c.textPosition = .zero;CTLineDraw(line,c);c.restoreGState()
}
func drawImage(_ c:CGContext,_ image:CGImage,_ rect:CGRect,alpha:CGFloat=1) {
    c.saveGState();c.setAlpha(alpha);c.translateBy(x:rect.minX,y:rect.maxY);c.scaleBy(x:1,y:-1);c.draw(image,in:CGRect(origin:.zero,size:rect.size));c.restoreGState()
}
func rounded(_ c:CGContext,_ rect:CGRect,radius:CGFloat,fill:CGColor,stroke:CGColor?=nil) {
    c.addPath(CGPath(roundedRect:rect,cornerWidth:radius,cornerHeight:radius,transform:nil));c.setFillColor(fill);c.fillPath()
    if let stroke { c.addPath(CGPath(roundedRect:rect,cornerWidth:radius,cornerHeight:radius,transform:nil));c.setStrokeColor(stroke);c.setLineWidth(1.2);c.strokePath() }
}
func loadImage(_ path:URL) throws -> CGImage {
    guard let source=CGImageSourceCreateWithURL(path as CFURL,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil) else {throw RenderFailure("Image missing: \(path.path)")};return image
}
final class Frames {
    let directory:URL
    var images:[Int:CGImage]=[:]
    init(_ directory:URL){self.directory=directory}
    func image(_ number:Int) throws -> CGImage {
        let n=min(284,max(0,number))
        if let image=images[n]{return image}
        let image=try loadImage(directory.appendingPathComponent(String(format:"frame-%04d.jpg",n)))
        if images.count>5{images.removeAll(keepingCapacity:true)}
        images[n]=image;return image
    }
}
final class Design {
    let frames:Frames
    let brand:CGImage
    let drag:CGImage?
    init(_ directory:URL) throws {
        frames=Frames(directory);brand=try loadImage(directory.appendingPathComponent("brand-icon.png"))
        let native=NSWorkspace.shared.icon(forFile:"/System/Applications/App Store.app")
        if let rep=native.tiffRepresentation,let source=CGImageSourceCreateWithData(rep as CFData,nil) {drag=CGImageSourceCreateImageAtIndex(source,0,nil)}else{drag=nil}
    }
    func background(_ c:CGContext,_ t:Double){
        c.setFillColor(color(0.025,0.035,0.075));c.fill(CGRect(x:0,y:0,width:width,height:height))
        let gradient=CGGradient(colorsSpace:CGColorSpace(name:CGColorSpace.sRGB),colors:[color(0.23,0.14,0.46,0.65),color(0.05,0.06,0.14,0)] as CFArray,locations:[0,1])!
        c.drawRadialGradient(gradient,startCenter:CGPoint(x:1470+sin(t*0.12)*60,y:410),startRadius:0,endCenter:CGPoint(x:1470,y:410),endRadius:1050,options:[])
        c.setStrokeColor(color(0.6,0.5,1,0.045));c.setLineWidth(1)
        for row in 0..<7 { let y=CGFloat(row)*180+80;c.move(to:CGPoint(x:0,y:y));c.addLine(to:CGPoint(x:1920,y:y));c.strokePath() }
    }
    func draw(_ c:CGContext,time t:Double) throws {
        c.saveGState();c.translateBy(x:0,y:CGFloat(height));c.scaleBy(x:1,y:-1)
        background(c,t)
        if t < 3 {
            let enter=smooth(t/0.65),leave=1-smooth((t-2.5)/0.5)
            c.saveGState();c.setAlpha(enter*leave)
            let dy=CGFloat((1-enter)*26)
            drawImage(c,brand,CGRect(x:880,y:208+dy,width:160,height:160))
            text(c,"LaunchDock",x:960,y:382+dy,size:88,weight:"Semibold",center:true)
            text(c,"让常用应用，触手可及",x:960,y:510+dy,size:34,color:color(0.73,0.74,0.84),center:true)
            text(c,"搜索   ·   启动   ·   整理",x:960,y:627+dy,size:23,color:color(0.67,0.59,1),center:true)
            c.restoreGState()
        } else if t < 23 {
            drawImage(c,brand,CGRect(x:86,y:49,width:42,height:42))
            text(c,"LaunchDock",x:142,y:51,size:27,weight:"Medium")
            text(c,"专为 Mac，原生打造",x:1570,y:57,size:20,color:color(0.56,0.58,0.69))
            let start:Double,end:Double,number:String,title:[String],subtitle:[String],source:Double
            if t<8 {start=3;end=8;number="01 / 看见";title=["常用应用","一眼找到"];subtitle=["熟悉的网格，清晰的布局。","打开 LaunchDock，即刻就位。"];source=(t-3)*15}
            else if t<14 {start=8;end=14;number="02 / 直达";title=["输入名字","快速直达"];subtitle=["少一点寻找，多一点专注。","点击图标，应用随即启动。"];source=75+(t-8)*12.5}
            else {start=14;end=23;number="03 / 整理";title=["拖拽归类","整齐，刚刚好"];subtitle=["把常用应用放在一起。","整理顺手，使用更顺心。"];source=150+(t-14)*15}
            let local=t-start,enter=smooth(local/0.45),leave=1-smooth((t-(end-0.3))/0.3)
            c.saveGState();c.setAlpha(enter*leave)
            let slide=CGFloat((1-enter)*22)
            text(c,number,x:96,y:238+slide,size:22,color:color(0.68,0.60,1),weight:"Medium")
            for (i,line) in title.enumerated(){text(c,line,x:92,y:314+CGFloat(i)*88+slide,size:66,weight:"Semibold")}
            for (i,line) in subtitle.enumerated(){text(c,line,x:96,y:536+CGFloat(i)*40+slide,size:24,color:color(0.66,0.68,0.77))}
            rounded(c,CGRect(x:96,y:780,width:380,height:3),radius:1.5,fill:color(1,1,1,0.08))
            rounded(c,CGRect(x:96,y:780,width:380*CGFloat(min(1,local/(end-start))),height:3),radius:1.5,fill:color(0.65,0.53,1))
            let frame=CGRect(x:574+slide,y:172,width:1250,height:781.25)
            c.saveGState();c.setShadow(offset:CGSize(width:0,height:24),blur:60,color:color(0,0,0,0.5))
            rounded(c,frame,radius:24,fill:color(0.10,0.075,0.22));c.restoreGState()
            c.saveGState();c.addPath(CGPath(roundedRect:frame,cornerWidth:24,cornerHeight:24,transform:nil));c.clip()
            let opacity=t>=8 && t<14 ? 1-smooth((local-4.55)/0.65):1
            if opacity<1 {
                drawImage(c,try frames.image(95),frame,alpha:0.12)
                text(c,"即刻响应",x:frame.midX,y:frame.midY-24,size:44,color:color(0.92,0.89,1),weight:"Medium",center:true)
                text(c,"启动之后，回到你的节奏",x:frame.midX,y:frame.midY+43,size:25,color:color(0.66,0.63,0.77),center:true)
            }
            let frameNumber=Int(t>=8 && t<14 ? min(source,134):source)
            drawImage(c,try frames.image(frameNumber),frame,alpha:opacity)
            if t>=14 && local>=1 && local<2.4 {
                let p=smooth((local-1)/1.35)
                let px=256+(435-256)*p,py=168-sin(p*Double.pi)*38
                let sx=frame.minX+CGFloat(px)*frame.width/1280,sy=frame.minY+CGFloat(py)*frame.height/800
                if let drag {
                    c.saveGState();c.setShadow(offset:CGSize(width:0,height:7),blur:16,color:color(0,0,0,0.35))
                    drawImage(c,drag,CGRect(x:sx-58,y:sy-58,width:116,height:116),alpha:0.92);c.restoreGState()
                }
                pointer(c,CGPoint(x:sx+30,y:sy+40),pressed:true)
            }
            c.restoreGState()
            c.addPath(CGPath(roundedRect:frame,cornerWidth:24,cornerHeight:24,transform:nil));c.setStrokeColor(color(0.83,0.79,1,0.18));c.setLineWidth(1.5);c.strokePath()
            c.restoreGState()
        } else {
            let local=t-23,enter=smooth(local/0.6),leave=1-smooth((local-4.6)/0.4)
            c.saveGState();c.setAlpha(enter*leave)
            drawImage(c,brand,CGRect(x:890,y:170,width:140,height:140))
            text(c,"LaunchDock",x:960,y:346,size:80,weight:"Semibold",center:true)
            text(c,"让每一次打开，都更顺手",x:960,y:458,size:34,color:color(0.77,0.77,0.86),center:true)
            let labels=["快速搜索","拖拽整理","触发角唤起"]
            for (i,label) in labels.enumerated(){
                let rect=CGRect(x:573+CGFloat(i)*264,y:598,width:246,height:68)
                rounded(c,rect,radius:34,fill:color(0.6,0.48,1,0.09),stroke:color(0.65,0.54,1,0.22))
                text(c,label,x:rect.midX,y:616,size:24,color:color(0.78,0.72,1),center:true)
            }
            text(c,"macOS 26+  ·  原生 SwiftUI / AppKit",x:960,y:748,size:21,color:color(0.48,0.50,0.62),center:true)
            text(c,"yishen@mdashen.com",x:960,y:803,size:21,color:color(0.55,0.53,0.68),center:true)
            c.restoreGState()
        }
        c.restoreGState()
    }
    func pointer(_ c:CGContext,_ point:CGPoint,pressed:Bool){
        c.saveGState();c.translateBy(x:point.x,y:point.y)
        if pressed {rounded(c,CGRect(x:-17,y:-17,width:34,height:34),radius:17,fill:color(0.75,0.66,1,0.23))}
        c.setShadow(offset:CGSize(width:1,height:2),blur:4,color:color(0,0,0,0.5))
        c.move(to:.zero);c.addLine(to:CGPoint(x:1,y:26));c.addLine(to:CGPoint(x:8,y:20));c.addLine(to:CGPoint(x:13,y:31));c.addLine(to:CGPoint(x:18,y:28));c.addLine(to:CGPoint(x:13,y:18));c.addLine(to:CGPoint(x:25,y:18));c.closePath();c.setFillColor(color(1,1,1));c.setStrokeColor(color(0.12,0.1,0.2));c.setLineWidth(1.5);c.drawPath(using:.fillStroke);c.restoreGState()
    }
}
@main struct RenderPromo {
    static func main() async {
        do {try await render()}catch{print("RENDER FAILED: \(error)");exit(1)}
    }
    static func render() async throws {
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let dir=root.appendingPathComponent("media/launchdock-promo")
        let design=try Design(dir.appendingPathComponent("frames"))
        let raw=dir.appendingPathComponent("picture.mp4")
        try? FileManager.default.removeItem(at:raw)
        let writer=try AVAssetWriter(outputURL:raw,fileType:.mp4)
        let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:width,AVVideoHeightKey:height,AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:10_000_000,AVVideoExpectedSourceFrameRateKey:fps,AVVideoMaxKeyFrameIntervalKey:60,AVVideoProfileLevelKey:AVVideoProfileLevelH264HighAutoLevel]])
        input.expectsMediaDataInRealTime=false
        let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:width,kCVPixelBufferHeightKey as String:height,kCVPixelBufferIOSurfacePropertiesKey as String:[:] as [String:Any]])
        writer.add(input);guard writer.startWriting() else{throw writer.error ?? RenderFailure("Writer start failed")};writer.startSession(atSourceTime:.zero)
        for frame in 0..<Int(duration*Double(fps)) {
            while !input.isReadyForMoreMediaData {if writer.status == .failed{throw writer.error ?? RenderFailure("Writer failed")};try await Task.sleep(for:.milliseconds(2))}
            try autoreleasepool {
                var buffer:CVPixelBuffer?
                guard let pool=adaptor.pixelBufferPool,CVPixelBufferPoolCreatePixelBuffer(nil,pool,&buffer)==kCVReturnSuccess,let buffer else{throw RenderFailure("Pixel buffer allocation")}
                CVPixelBufferLockBaseAddress(buffer,[])
                guard let c=CGContext(data:CVPixelBufferGetBaseAddress(buffer),width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedFirst.rawValue|CGBitmapInfo.byteOrder32Little.rawValue) else {throw RenderFailure("Frame CGContext")}
                try design.draw(c,time:Double(frame)/Double(fps))
                if frame==48,let image=c.makeImage(){try savePNG(image,dir.appendingPathComponent("poster.png"))}
                CVPixelBufferUnlockBaseAddress(buffer,[])
                guard adaptor.append(buffer,withPresentationTime:CMTime(value:Int64(frame),timescale:Int32(fps))) else{throw writer.error ?? RenderFailure("Append failed")}
            }
            if frame%120==0{print("Rendered \(frame)/840");fflush(stdout)}
        }
        input.markAsFinished();await writer.finishWriting()
        guard writer.status == .completed else{throw writer.error ?? RenderFailure("Video finalize failed")}
        let music=dir.appendingPathComponent("original-score.m4a");try makeMusic(music)
        let composition=AVMutableComposition()
        let video=AVURLAsset(url:raw),audio=AVURLAsset(url:music)
        guard let sourceVideo=try await video.loadTracks(withMediaType:.video).first,let sourceAudio=try await audio.loadTracks(withMediaType:.audio).first,
              let v=composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid),let a=composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid) else{throw RenderFailure("Tracks missing")}
        let range=CMTimeRange(start:.zero,duration:CMTime(seconds:duration,preferredTimescale:600))
        try v.insertTimeRange(range,of:sourceVideo,at:.zero);try a.insertTimeRange(range,of:sourceAudio,at:.zero)
        let final=root.appendingPathComponent("media/LaunchDock-Promo-1080p.mp4")
        try? FileManager.default.removeItem(at:final)
        guard let export=AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetPassthrough) else{throw RenderFailure("Export unavailable")}
        export.shouldOptimizeForNetworkUse=true
        try await export.export(to:final,as:.mp4)
        print("VIDEO COMPLETE: \(final.path)")
    }
    static func makeMusic(_ url:URL) throws {
        try? FileManager.default.removeItem(at:url)
        let sampleRate=48000.0,count=Int(duration*sampleRate)
        let format=AVAudioFormat(standardFormatWithSampleRate:sampleRate,channels:2)!
        let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(count))!;buffer.frameLength=AVAudioFrameCount(count)
        let chords:[[Double]]=[[130.8128,164.8138,195.9977,246.9417],[110,130.8128,164.8138,195.9977],[87.3071,110,130.8128,164.8138],[97.9989,123.4708,146.8324,164.8138]]
        let beat=60.0/102,bar=beat*4
        for i in 0..<count {
            let t=Double(i)/sampleRate
            let chord=chords[Int(t/bar)%4],phase=t.truncatingRemainder(dividingBy:bar)
            let envelope=min(1,t/1.2)*min(1,(duration-t)/1.7)
            var left=0.0,right=0.0
            for (n,f) in chord.enumerated(){
                let swell=0.6+0.4*sin(Double.pi*phase/bar)
                let pad=0.0085*swell*sin(2*Double.pi*f*t)
                left += pad;right += 0.0085*swell*sin(2*Double.pi*f*t+0.04*Double(n))
            }
            let step=Int(t/(beat/2)),age=t-Double(step)*beat/2
            let note=chord[step%4]*2
            let pluck=0.026*(1-exp(-age/0.012))*exp(-age/0.20)*(sin(2*Double.pi*note*age)+0.15*sin(4*Double.pi*note*age))
            left += pluck*(step%2==0 ? 1:0.65);right += pluck*(step%2==0 ? 0.65:1)
            buffer.floatChannelData![0][i]=Float(left*envelope*4);buffer.floatChannelData![1][i]=Float(right*envelope*4)
        }
        let file=try AVAudioFile(forWriting:url,settings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:sampleRate,AVNumberOfChannelsKey:2,AVEncoderBitRateKey:160000],commonFormat:.pcmFormatFloat32,interleaved:false)
        try file.write(from:buffer)
    }
}
func savePNG(_ image:CGImage,_ url:URL) throws {
    guard let dest=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil) else{throw RenderFailure("PNG destination")}
    CGImageDestinationAddImage(dest,image,nil);guard CGImageDestinationFinalize(dest) else{throw RenderFailure("PNG encoding")}
}
