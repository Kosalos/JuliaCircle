import UIKit
import Metal
import MetalKit

let cReMin:Float = -1.2
let cReMax:Float = +1.2
let cImMin:Float = -1
let cImMax:Float = +1
let multMin:Float = 0.6
let multMax:Float = 3
var reHop:Float = 0
var imHop:Float = (cImMax - cImMin) / Float(4000)
var multHop:Float = (multMax - multMin) / Float(60)

var cycleColorsFlag:Bool = false
var deltaZoom:Float = 0
var control = Control()
var cBuffer:MTLBuffer! = nil
var jBuffer:MTLBuffer! = nil

class ViewController: UIViewController {
    var reDelta:Float = 0
    var imDelta:Float = 0
    var multDelta:Float = 0
    var isScrolling:Bool = false
    var timer = Timer()
    var inTexture: MTLTexture!
    var outTexture: MTLTexture!
    let bytesPerPixel: Int = 4
    var pipeline1: MTLComputePipelineState!
    var pipeline2: MTLComputePipelineState!
    let queue = DispatchQueue(label: "Julia")
    lazy var device: MTLDevice! = MTLCreateSystemDefaultDevice()
    lazy var defaultLibrary: MTLLibrary! = { self.device.makeDefaultLibrary() }()
    lazy var commandQueue: MTLCommandQueue! = { return self.device.makeCommandQueue() }()
    let threadGroupCount = MTLSizeMake(16, 16, 1)
    lazy var threadGroups: MTLSize = { MTLSizeMake(Int(self.outTexture.width) / self.threadGroupCount.width, Int(self.outTexture.height) / self.threadGroupCount.height, 1) }()
    
    @IBOutlet var imageView: UIImageView!
    @IBOutlet var label1: UILabel!
    @IBOutlet var label2: UILabel!
    @IBOutlet var label3: UILabel!
    @IBOutlet var slider1: UISlider!
    @IBOutlet var slider2: UISlider!
    @IBOutlet var slider3: UISlider!
    @IBOutlet var slider4: UISlider!

    @IBOutlet var ReMButton: UIButton!
    @IBOutlet var RePButton: UIButton!
    @IBOutlet var imMButton: UIButton!
    @IBOutlet var imPButton: UIButton!
    @IBOutlet var muMButton: UIButton!
    @IBOutlet var muPButton: UIButton!
    @IBOutlet var circleButton: UIButton!
    
    let bColors:[UIColor] = [
        UIColor(red:0.5, green:0.5, blue:0.5, alpha:1),
        UIColor(red:0.8, green:0.4, blue:0.0, alpha:1),
    ]
    
    func buttonPressCommon(_ sender: UIButton) {
        ReMButton.backgroundColor = bColors[0]
        RePButton.backgroundColor = bColors[0]
        imMButton.backgroundColor = bColors[0]
        imPButton.backgroundColor = bColors[0]
        muMButton.backgroundColor = bColors[0]
        muPButton.backgroundColor = bColors[0]
        sender.backgroundColor = bColors[1]

        reDelta = 0
        imDelta = 0
        multDelta = 0
        determineDeltas()
        isScrolling = true
    }

    @IBAction func reMinus(_ sender: UIButton) {
        buttonPressCommon(sender)
        reDelta = -reHop
    }
    
    @IBAction func rePlus(_ sender: UIButton) {
        buttonPressCommon(sender)
        reDelta = +reHop
    }
    
    @IBAction func imMinus(_ sender: UIButton) {
        buttonPressCommon(sender)
        imDelta = -imHop
    }
    
    @IBAction func imPlus(_ sender: UIButton) {
        buttonPressCommon(sender)
        imDelta = +imHop
    }
    
    @IBAction func multMinus(_ sender: UIButton) {
        buttonPressCommon(sender)
        multDelta = -multHop
    }
    
    @IBAction func multPlus(_ sender: UIButton) {
        buttonPressCommon(sender)
        multDelta = +multHop
    }

    @IBAction func scrollRelease(_ sender: UIButton) {
        sender.backgroundColor = bColors[0]
        isScrolling = false
    }

    @IBAction func shadowPressed(_ sender: UIButton) {
        control.shadow += 1
        if control.shadow > 2 { control.shadow = 0 }
        needsPaint = true
    }
    
    func setButtonBackground(_ sender: UIButton, _ onoff:Bool) {
        let colorIndex:Int = onoff ? 1 : 0
        sender.backgroundColor = bColors[colorIndex]
    }
    
    @IBAction func toggleCycle(_ sender: UIButton) {
        cycleColorsFlag = !cycleColorsFlag
        setButtonBackground(sender,cycleColorsFlag)
    }
    
    @IBAction func resetButtonPressed(_ sender: UIButton) { reset() }
    @IBAction func colorButtonPressed(_ sender: UIButton) { loadNextColorMap();  needsPaint = true }
    @IBAction func zoomMinusDown(_ sender: UIButton) { deltaZoom = 0.98 }
    @IBAction func zoomMinusUp(_ sender: UIButton) { deltaZoom = 0 }
    @IBAction func zoomPlusDown(_ sender: UIButton) { deltaZoom = 1.02 }
    @IBAction func zoomPlusUp(_ sender: UIButton) { deltaZoom = 0 }
    
    @IBAction func circleButtonPressed(_ sender: UIButton) {
        control.circle = !control.circle
        setButtonBackground(sender,control.circle)
        needsPaint = true
    }

    override var prefersStatusBarHidden: Bool { return true }

    //MARK: -
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        do {
            guard let kf1 = defaultLibrary.makeFunction(name: "juliaShader")  else { fatalError() }
            pipeline1 = try device.makeComputePipelineState(function: kf1)
            
            guard let kf2 = defaultLibrary.makeFunction(name: "shadowShader")  else { fatalError() }
            pipeline2 = try device.makeComputePipelineState(function: kf2)
        }
        catch { fatalError("error creating pipelines") }

        let SIZE = 1024
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: SIZE,
            height: SIZE,
            mipmapped: false)
        inTexture = self.device.makeTexture(descriptor: textureDescriptor)!
        outTexture = self.device.makeTexture(descriptor: textureDescriptor)!
        
        control.ratio = 0.5
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        cBuffer = device.makeBuffer(bytes: &control, length: MemoryLayout<Control>.stride, options: MTLResourceOptions.storageModeShared)
        jBuffer = device.makeBuffer(bytes:colorMap1, length: MemoryLayout<float3>.stride * 256, options: MTLResourceOptions.storageModeShared)

        reset()
        needsPaint = true
        timer = Timer.scheduledTimer(timeInterval: 1.0/20.0, target:self, selector: #selector(timerHandler), userInfo: nil, repeats:true)
    }
    
    //MARK: -
    
    func reset() {
        control.base.x = -0.152718604
        control.base.y = -0.89949572
        control.zoom = 710
        control.cRe = -0.73431158
        control.cIm = 0.218115941
        control.mult = 1.98369563
        control.cycleAmount = 0
        control.gray = false
        updateLabels()
        updateSliders()
        
        needsPaint = true
    }
    
    //MARK: -
    
    var tapScrollX:Float = 0
    var tapScrollY:Float = 0
    var tapScrollCount:Int = 0
    var needsPaint:Bool = false

    @objc func timerHandler() {
        
        if cycleColorsFlag {
            control.cycleAmount += 1
            if control.cycleAmount > 255 { control.cycleAmount = 0 }
            needsPaint = true
        }

        if isScrolling {
            control.cRe += reDelta
            control.cIm += imDelta
            control.mult += multDelta
            
            updateSliders()
            updateLabels()
            needsPaint = true
        }
        
        if tapScrollCount > 0 {
            tapScrollCount -= 1
            control.base.x += tapScrollX
            control.base.y += tapScrollY
            needsPaint = true
        }
        
        if deltaZoom != 0 {
            alterZoom(deltaZoom)
            needsPaint = true
        }
        
        if needsPaint {
            needsPaint = false
            updateImage()
        }
    }
    
    //MARK: -
    
    @IBAction func sliderPressed(_ sender: UISlider) {
        switch sender {
        case slider1 : control.cRe  = cReMin  + (cReMax - cReMin) * sender.value
        case slider2 : control.cIm  = cImMin  + (cImMax - cImMin) * sender.value
        case slider3 : control.mult = multMin + (multMax - multMin) * sender.value
        case slider4 : control.ratio = 1.0 - sender.value
        default : break
        }

        updateLabels()
        needsPaint = true
    }
    
    func updateSliders() {
        slider1.value = (control.cRe - cReMin) / (cReMax - cReMin)
        slider2.value = (control.cIm - cImMin) / (cImMax - cImMin)
        slider3.value = (control.mult - multMin) / (multMax - multMin)
    }

    func updateImage() {
        queue.async {
            self.calcJuliaSet()
            DispatchQueue.main.async { self.imageView.image = self.image(from: self.outTexture) }
        }
    }
    
    func updateLabels() {
        label1.text = String(format:"%+6.4f",control.cRe)
        label2.text = String(format:"%+6.4f",control.cIm)
        label3.text = String(format:"%+6.4f",control.mult)
    }
    
    func determineDeltas() {
        let zz = control.zoom * 5
        reHop = (cReMax - cReMin) / zz
        imHop = (cImMax - cImMin) / zz
        multHop = (multMax - multMin) * 5 / zz
    }
    
    //MARK: -
    
    func alterZoom(_ amt:Float) {
        let xc:Float = control.base.x + Float(imageView.bounds.width / 2) / control.zoom
        let yc:Float = control.base.y + Float(imageView.bounds.height / 2) / control.zoom
        
        control.zoom *= amt
        
        let min:Float = 150
        if control.zoom < min { control.zoom = min }
        
        //Swift.print("Zoom ",control.zoom)
        control.base.x = xc - Float(imageView.bounds.width / 2) / control.zoom
        control.base.y = yc - Float(imageView.bounds.height / 2) / control.zoom
        
        needsPaint = true
    }
    
    //MARK: -

    @IBAction func tapGesture(_ sender: UITapGestureRecognizer) {
        let t = sender.location(in: nil)
        tapScrollX = Float(t.x - self.imageView.bounds.width/2)  / (control.zoom * Float(12))
        tapScrollY = Float(t.y - self.imageView.bounds.height/2) / (control.zoom * Float(12))
        tapScrollCount = 10
    }
    
    @IBAction func panGesture(_ sender: UIPanGestureRecognizer) {
        let t = sender.translation(in: self.view)
        let scale:Float = 0.03 / control.zoom

        control.base.x -= Float(t.x) * scale
        control.base.y -= Float(t.y) * scale

        needsPaint = true
    }
    
    @IBAction func pinchGesture(_ sender: UIPinchGestureRecognizer) {
        var t = Float(sender.scale)
        t = Float(1) - (Float(1) - t) / Float(20)

        //Swift.print("Pinch gesture ",t)

        alterZoom(t)
    }

    //MARK: -

    func calcJuliaSet() {
        
        // inTexture = Julia set
        cBuffer.contents().copyBytes(from: &control, count:MemoryLayout<Control>.stride)
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        commandEncoder.setComputePipelineState(pipeline1)
        commandEncoder.setTexture(inTexture, index: 0)
        commandEncoder.setBuffer(cBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(jBuffer, offset: 0, index: 1)
        commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        commandEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // outTexture = inTexture with shadowing applied
        if true {
            let commandBuffer = commandQueue.makeCommandBuffer()!
            let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
            
            commandEncoder.setComputePipelineState(pipeline2)
            commandEncoder.setTexture(inTexture, index: 0)
            commandEncoder.setTexture(outTexture, index: 1)
            commandEncoder.setBuffer(cBuffer, offset: 0, index: 0)
            commandEncoder.setBuffer(jBuffer, offset: 0, index: 1)
            commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
            commandEncoder.endEncoding()
            
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
    }
    
    //MARK: -
    
    var colorMapIndex:Int = 0
    
    func loadNextColorMap() {
        colorMapIndex += 1
        if colorMapIndex > 4 { colorMapIndex = 0 }
        
        let jbSize = MemoryLayout<float3>.stride * 256
        control.gray = false

        switch colorMapIndex {
        case 0 : jBuffer.contents().copyBytes(from:colorMap1, count:jbSize)
        case 1 : jBuffer.contents().copyBytes(from:colorMap2, count:jbSize)
        case 2 : jBuffer.contents().copyBytes(from:colorMap3, count:jbSize)
        case 3 : jBuffer.contents().copyBytes(from:colorMap4, count:jbSize)
        case 4 : control.gray = true
        default : break
        }
    }
    
    //MARK: -
    // edit Scheme, Options, Metal API Validation : Disabled
    //the fix is to turn off Metal API validation under Product -> Scheme -> Options
    
//    func texture(from image: UIImage) -> MTLTexture {
//        guard let cgImage = image.cgImage else { fatalError("Can't open image \(image)") }
//        
//        let textureLoader = MTKTextureLoader(device: self.device)
//        do {
//            let textureOut = try textureLoader.newTexture(cgImage:cgImage)
//            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
//                pixelFormat: textureOut.pixelFormat,
//                width: textureOut.width,
//                height: textureOut.height,
//                mipmapped: false)
//            outTexture = self.device.makeTexture(descriptor: textureDescriptor)
//            return textureOut
//        }
//        catch {
//            fatalError("Can't load texture")
//        }
//    }
    
    func image(from texture: MTLTexture) -> UIImage {
        let imageByteCount = texture.width * texture.height * bytesPerPixel
        let bytesPerRow = texture.width * bytesPerPixel
        var src = [UInt8](repeating: 0, count: Int(imageByteCount))
        
        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
        texture.getBytes(&src, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        let bitmapInfo = CGBitmapInfo(rawValue: (CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitsPerComponent = 8
        let context = CGContext(data: &src,
                                width: texture.width,
                                height: texture.height,
                                bitsPerComponent: bitsPerComponent,
                                bytesPerRow: bytesPerRow,
                                space: colorSpace,
                                bitmapInfo: bitmapInfo.rawValue)
        
        let dstImageFilter = context?.makeImage()
        
        return UIImage(cgImage: dstImageFilter!, scale: 0.0, orientation: UIImageOrientation.up)
    }
}

