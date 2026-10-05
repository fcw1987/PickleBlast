import AppKit
import Foundation
let root=URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let image=NSImage(contentsOf: root.appendingPathComponent("ArtSources/ArcadeV1/generated-master.png"))!
var rect=CGRect(origin:.zero,size:image.size)
let source=image.cgImage(forProposedRect:&rect,context:nil,hints:nil)!
let bitmap=NSBitmapImageRep(cgImage:source)
let names=["target_paddle_cyan","target_paddle_lime","target_paddle_magenta","target_cone","target_basket","target_basket_damaged"]
var records:[[String:Any]]=[]
for (index,name) in names.enumerated() {
 let ox=(index%3)*512, oy=(index/3)*512
 var x0=512,y0=512,x1=0,y1=0
 for y in 0..<512 { for x in 0..<512 {
  if bitmap.colorAt(x:ox+x,y:oy+y)!.alphaComponent > 0.5 { x0=min(x0,x);y0=min(y0,y);x1=max(x1,x+1);y1=max(y1,y+1) }
 }}
 let crop=CGRect(x:ox+x0,y:oy+y0,width:x1-x0,height:y1-y0)
 let clipped=source.cropping(to:crop)!
 let ctx=CGContext(data:nil,width:256,height:256,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 ctx.interpolationQuality = .high
 let scale=index<3 ? 112.0/Double(x1-x0) : 192.0/Double(max(x1-x0,y1-y0))
 let w=Double(x1-x0)*scale, h=Double(y1-y0)*scale
 // Paddles retain the approved head-width/head-center registration. Bottom
 // handles stay decorative; object collider uses the existing alpha diameter.
 let draw=CGRect(x:(256-w)/2,y:index<3 ? 256-36-h : (256-h)/2,width:w,height:h)
 ctx.draw(clipped,in:draw)
 let output=NSBitmapImageRep(cgImage:ctx.makeImage()!).representation(using:.png,properties:[:])!
 try output.write(to:root.appendingPathComponent("ArtSources/ArcadeV1/"+name+".png"))
 records.append(["name":name,"sourceCrop":[crop.minX,crop.minY,crop.width,crop.height],"outputRect":[draw.minX,draw.minY,draw.width,draw.height]])
}
let data=try JSONSerialization.data(withJSONObject:records,options:[.prettyPrinted,.sortedKeys]);try data.write(to:root.appendingPathComponent("ArtSources/ArcadeV1/normalization.json"))
