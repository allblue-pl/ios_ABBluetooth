import CoreBluetooth
import SwiftUI

import ABLibs

public class ABBluetoothPrinter: NSObject, CBPeripheralDelegate, CBCentralManagerDelegate {
//    static let packetLength = 32
    static let maxCompareLimit = 1000
    
    private var printerAddress: String?
    private var serviceFn: ((_ peripheral: CBPeripheral) -> [ABBluetoothPrintingServiceInfo]?)?
    private var printImagesFn: ((_ peripheral: CBPeripheral) -> (Int, [ () -> UIImage? ], String?))?
    private var printingServiceInfo: ABBluetoothPrintingServiceInfo?
//    private var printImagesFn: ((_ peripheral: CBPeripheral) -> (Int, [ () -> UIImage? ], String?))?
//    private var imageFns: [ () -> UIImage? ]
    private var imageFns: [ () -> UIImage? ]
    private var paperWidth: Int
    
    private var centralManager: CBCentralManager!
    
    private var peripheral: CBPeripheral!
    private var characteristic: CBCharacteristic!
    private var dataToSend: Data!
    private var compareLimit: Int
    
    private var errorFn: (_ errorMessage: String) -> Void
    private var messageFn: (_ message: String) -> Void
    
    private var warnings: [String]
    
    public init(errorFn: @escaping ((_ errorMessage: String) -> Void), messageFn: @escaping ((_ warningMessage: String) -> Void)) {
        self.compareLimit = 0
        self.errorFn = errorFn
        self.messageFn = messageFn
        self.printingServiceInfo = nil
        self.warnings = []

        self.imageFns = []
        self.paperWidth = 0
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if (peripheral != self.peripheral) {
            return
        }
        
        self.peripheral.discoverServices(nil)
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {

    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [ String: Any ], rssi RSSI: NSNumber) {
        print("ABBluetoothPrinter -> Comparing " + peripheral.identifier.uuidString + ":" + self.printerAddress!)
        
        if (peripheral.identifier.uuidString == self.printerAddress && self.peripheral == nil) {
            print("ABBluetoothPrinter -> Dicovered: " + (peripheral.name ?? "-"))
            
            self.peripheral = peripheral
            self.peripheral.delegate = self
            
            self.centralManager.stopScan()
            
            self.centralManager.connect(self.peripheral, options: nil)
        } else {
            compareLimit -= 1
            if (compareLimit <= 0) {
                self.centralManager.stopScan()
                errorFn(Lang.t(TABBluetooth.errors_CannotFindPrinter))
                reset()
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {

        guard let printingServiceInfo else {
            print("ABBluetoothPrinter -> Error: 'printingServiceInfo' not set.")
            errorFn(Lang.t(TABBluetooth.errors_UnknownError))
            reset()
            return
        }
        
        for printingCharacteristic in printingServiceInfo.characteristicsUUIDs {
            guard let characteristics = service.characteristics else {
                errorFn(Lang.t(TABBluetooth.errors_CannotFindCharacteristics))
                reset()
                return
            }
            
            for characteristic in characteristics {
                if printingCharacteristic == nil {
                    if (characteristic.properties.rawValue & CBCharacteristicProperties.writeWithoutResponse.rawValue != 0) {
                        self.characteristic = characteristic
                        warnings.append(Lang.t(TABBluetooth.warnings_UnknownPrintingCharacteristic))
                        break
                    }
                }
                
                if characteristic.uuid.uuidString == printingCharacteristic {
                    self.characteristic = characteristic
                    break
                }
            }
            
            if self.characteristic != nil {
                break
            }
        }
        
        guard self.characteristic != nil else {
            errorFn(Lang.t(TABBluetooth.errors_CannotFindSupportedProtocol))
            reset()
            return
        }

        guard printImagesFn != nil else {
            print("ABBluetoothPrinter -> Error: 'printImageFn' not set.")
            errorFn(Lang.t(TABBluetooth.errors_UnknownError))
            reset()
            return
        }
    
        let (paperWidth_T, imageFns_T, message) = printImagesFn!(peripheral)
        paperWidth = paperWidth_T
        imageFns = imageFns_T
        
        if let message {
            messageFn(message)
        }
        
        if imageFns.count > 0 {
            let image = imageFns[0]()
            imageFns.remove(at: 0)
            if let image {
                sendImageData(img: image)
            }
        } else {
            errorFn(Lang.t(TABBluetooth.errors_CannotGenerateImage))
            reset()
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        var s: CBService?
        guard let serviceFn else {
            print("ABBluetoothPrinter -> Error: 'printingServiceInfo' not set.")
            errorFn(Lang.t(TABBluetooth.errors_UnknownError))
            reset()
            return
        }
        
        guard let printingServiceInfos = serviceFn(peripheral) else {
            print("ABBluetoothPrinter -> 'nil' result from 'serviceFn'.")
            errorFn(Lang.t(TABBluetooth.errors_UnknownError))
            reset()
            return
        }
        
        for printingServiceInfo in printingServiceInfos {
            if let services = peripheral.services {
                for service in services {
                    if printingServiceInfo.serviceUUID == nil {
                        s = service
                        self.printingServiceInfo = printingServiceInfo
                        warnings.append(Lang.t(TABBluetooth.warnings_UnknownPrintingService))
                        break
                    }
                    
                    if service.uuid.uuidString == printingServiceInfo.serviceUUID {
                        s = service
                        self.printingServiceInfo = printingServiceInfo
                        print("Printing Service UUID -> " + service.uuid.uuidString)
                        break
                    }
                }
            }
            
            if s != nil {
                break
            }
        }
        
        if let s {
            self.peripheral.discoverCharacteristics(nil, for: s)
        } else {
            errorFn(Lang.t(TABBluetooth.errors_CannotFindPrintingService))
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
//        if let data = characteristic.value {
//            let str = String(data: data, encoding: .ascii)
//            print("Characteristic response: \(characteristic) \(str)")
//        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
//        if let data = characteristic.value {
//            print("Yes " + String(data.count))
//        } else {
//            print("Nope")
//        }
    }
    
    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        let subData: Data! = self.extractData(from: &self.dataToSend)
        if subData == nil {
            if (imageFns.count > 0) {
                let image = imageFns[0]()
                imageFns.remove(at: 0)
                if let image {
                    sendImageData(img: image)
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.centralManager.cancelPeripheralConnection(self.peripheral)
                }
            }
            
            return
        }
            
        peripheral.writeValue(subData, for: self.characteristic, type: CBCharacteristicWriteType.withoutResponse)
    }
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("Central state update")
        if (central.state != .poweredOn) {
            print("Central state is not powered on")
        } else {
            print("Central scanning...")
            self.centralManager!.scanForPeripherals(withServices: nil, options: [ CBCentralManagerScanOptionAllowDuplicatesKey: true ])
        }
    }
    
    public func printImages(printerAddress: String, serviceFn: @escaping (_ peripheral: CBPeripheral) -> [ABBluetoothPrintingServiceInfo]?, printImagesFn: @escaping (_ peripheral: CBPeripheral) -> (Int, [ () -> UIImage? ], String?)) {
        self.printerAddress = printerAddress
        self.serviceFn = serviceFn
        self.printImagesFn = printImagesFn
//    public func printImages(printerAddress: String, printImagesFn: @escaping (_ peripheral: CBPeripheral) -> (Int, [ () -> UIImage? ], String?)) {
//        self.printerAddress = printerAddress
//        self.printImagesFn = printImagesFn
        
        self.peripheral = nil
        self.characteristic = nil
        self.compareLimit = ABBluetoothPrinter.maxCompareLimit
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
        
        var bluetoothPermission:Bool
        if #available(iOS 13.1, *) {
            bluetoothPermission = CBCentralManager.authorization == .allowedAlways
        } else if #available(iOS 13.0, *) {
            bluetoothPermission = CBCentralManager().authorization == .allowedAlways
        } else {
            bluetoothPermission = true
        }
        
        if (!bluetoothPermission) {
            print("No bluetooth permission.")
            
            errorFn(Lang.t(TABBluetooth.errors_NoBluetoothPermission))
            
            reset()
//            let alert = UIAlertController(title: "Brak Pozwolenia Bluetooth", message: "Żeby skorzystać z funkcji Bluetooth musisz zezwolić na jego wykorzystanie w ustawieniach telefonu.", preferredStyle: .alert)
//            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
//            
//            UIApplication.shared.windows.last?.rootViewController?.present(alert, animated: true)
        } else {
            print("Starting scanning...")
        }
    }
    
    private func extractData(from data: inout Data) -> Data? {
        guard data.count > 0 else {
            return nil
        }
        
        let maxLength = peripheral.maximumWriteValueLength(for: .withoutResponse)
        let length = min(maxLength, data.count)
        let range = 0..<length
        let subData = data.subdata(in: range)
        data.removeSubrange(range)
        
        return subData
    }
    
    private func reset() {
        printerAddress = nil
        printImagesFn = nil
        printingServiceInfo = nil
        warnings = []
//        self.printerAddress = nil
//        self.printImagesFn = nil
//        self.imageFns = []
//        self.paperWidth = 0
    }
    
    private func sendImageData(img: UIImage) {
        if (paperWidth == 0) {
            print("ABBluetoothPrinter -> Error: Paper width not set")
            return
        }
        let width = paperWidth
        
        let f = Float(width) / Float(img.size.width)
        let height = Int(Float(img.size.height) * f)

//        print("Size \(width) x \(height)")

        /* Scale Image */
        let image_Size = CGSize(width: width, height: height)
        let image_Rect = CGRect(x: 0, y: 0, width: image_Size.width, height: image_Size.height)

        UIGraphicsBeginImageContextWithOptions(image_Size, false, 1.0)

        img.draw(in: image_Rect)
        let image_UI = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        /* / Scale Image */

        let image_CG = img.cgImage

        let image_BitmapBytesForRow = Int(width * 4)
        let image_BitmapBytesCount = image_BitmapBytesForRow * height

        let image_ColorSpace = CGColorSpaceCreateDeviceRGB()

        let image_BitmapMemory = malloc(image_BitmapBytesCount)
        let image_BitmapInformation = CGImageAlphaInfo.premultipliedFirst.rawValue

        let image_ColorContext = CGContext(data: image_BitmapMemory, width: width, height: height, bitsPerComponent: 8, bytesPerRow: image_BitmapBytesForRow, space: image_ColorSpace, bitmapInfo: image_BitmapInformation)

        image_ColorContext?.clear(image_Rect)
        image_ColorContext?.draw(image_CG!, in: image_Rect)

//        if image_CG == nil {
//            print("Buuu")
//        } else {
//            print("JeJ")
//        }
//
//        return

        let image_Data = image_ColorContext?.data
        let image_DataType = image_Data?.assumingMemoryBound(to: UInt8.self)

        let extraHeight = 100

        var image: [UInt8] = [UInt8](repeating: 0, count: 8 + (width / 8) * (height + extraHeight))

        image[0] = 0x1d
        image[1] = 0x76
        image[2] = 0x30
        image[3] = 0x00
        image[4] = UInt8((width / 8) % 256)
        image[5] = UInt8((width / 8) / 256)
        image[6] = UInt8((height + extraHeight) % 256)
        image[7] = UInt8((height + extraHeight) / 256)

        for i in 0..<(height+extraHeight) {
            for j in 0..<(width / 8) {
                var colorByte: UInt8 = 0

                if (i < height) {
                    for k: UInt8 in 0..<8 {
                        let bmpX = i
                        let bmpY = j * 8 + Int(k)

                        let offset = 4 * ((width * bmpX) + bmpY)
                        //                    print("\(bmpX):\(bmpY)")
                        //                    print("Test: \(offset) : " + String(image_DataType?[offset + 1] ?? 255))
                        if (image_DataType?[offset + 1] ?? 255) < 128 {
                            colorByte |= 1 << (7 - k)
                        }
                    }
                }

                image[8 + i * (width / 8) + j] = colorByte
            }
        }


        free(image_BitmapMemory)

        var printerData: [UInt8] = [UInt8](repeating: 0, count: image.count + 2)
        /* Init */
        printerData[0] = 0x1b
        printerData[1] = 0x40
        /* Image */
        for i in 0..<image.count {
            printerData[2 + i] = image[i]
        }

        self.dataToSend = Data(printerData)
        let subData: Data! = self.extractData(from: &self.dataToSend)
        peripheral.writeValue(subData, for: self.characteristic, type: CBCharacteristicWriteType.withoutResponse)
    
    //        print(data)
    //        peripheral.writeValue(data, for: c, type: CBCharacteristicWriteType.withoutResponse)
    
    //        var subData: Data!
    //        while true {
    //            subData = self.extractData(from: &data)
    //            if subData == nil {
    //                break
    //            }
    //
    ////            print(subData!)
    //            peripheral.writeValue(subData, for: c, type: CBCharacteristicWriteType.withoutResponse)
    ////            print("Sent some data")
    //        }
    
            print("ABBluetoothPrinter -> Sent all data")
    
    //        self.centralManager.cancelPeripheralConnection(self.peripheral)
    }
}

public struct ABBluetoothPrintingServiceInfo {
    let serviceUUID: String?
    let characteristicsUUIDs: [String?]
    
    public init(_ serviceUUID: String?, _ characteristicsUUIDs: [String?]) {
        self.serviceUUID = serviceUUID
        self.characteristicsUUIDs = characteristicsUUIDs
    }
}

class ABBluetoothPrinterPeripheral: NSObject {
    public static let PrinterUUID = CBUUID.init(string: "")
    public static let PrintingServiceUUIDs = [ CBUUID.init(string: "18F0"), CBUUID.init(string: "1804") ]
//    public static let PrintingServiceUUID = CBUUID.init(string: "18F0")
//    public static let PrintingServiceUUID = CBUUID.init(string: "1804")
    
}
