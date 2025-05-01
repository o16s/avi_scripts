import usb.core
import usb.util
import sys
import time
import struct
import platform

def detailed_usb_device_info(device):
    """Get detailed information about a USB device"""
    info = {}
    
    try:
        info["vendor_id"] = hex(device.idVendor)
        info["product_id"] = hex(device.idProduct)
        info["bus"] = device.bus
        info["address"] = device.address
        
        try:
            info["manufacturer"] = usb.util.get_string(device, device.iManufacturer)
        except:
            info["manufacturer"] = "Unknown"
            
        try:
            info["product"] = usb.util.get_string(device, device.iProduct)
        except:
            info["product"] = "Unknown"
            
        try:
            info["serial"] = usb.util.get_string(device, device.iSerialNumber)
        except:
            info["serial"] = "Unknown"
    except:
        pass
        
    return info

def find_all_usb_devices():
    """Find and list all USB devices"""
    devices = list(usb.core.find(find_all=True))
    print(f"Found {len(devices)} USB devices in total")
    return devices

def find_uvc_cameras(devices):
    """Find UVC camera devices from all USB devices"""
    uvc_devices = []
    
    for device in devices:
        info = detailed_usb_device_info(device)
        
        # Check each configuration and interface to find video class devices
        is_uvc = False
        has_video_control = False
        has_video_streaming = False
        
        try:
            for cfg in device:
                for intf in cfg:
                    if intf.bInterfaceClass == 14:  # Video class
                        is_uvc = True
                        if intf.bInterfaceSubClass == 1:  # Video Control
                            has_video_control = True
                        elif intf.bInterfaceSubClass == 2:  # Video Streaming
                            has_video_streaming = True
        except:
            pass
            
        if is_uvc:
            info["is_uvc"] = True
            info["has_video_control"] = has_video_control
            info["has_video_streaming"] = has_video_streaming
            info["device"] = device
            uvc_devices.append(info)
    
    print(f"Found {len(uvc_devices)} UVC camera devices")
    return uvc_devices

def analyze_uvc_controls(device_info):
    """Analyze UVC control capabilities for a device"""
    device = device_info["device"]
    
    print(f"\nAnalyzing UVC controls for {device_info['product']} ({device_info['vendor_id']}:{device_info['product_id']})")
    
    # Constants for UVC control
    UVC_GET_CUR = 0x81
    UVC_GET_MIN = 0x82
    UVC_GET_MAX = 0x83
    UVC_GET_RES = 0x84
    UVC_GET_DEF = 0x87
    
    # UVC control selectors (common ones)
    controls = {
        "brightness": 0x02,
        "contrast": 0x03,
        "hue": 0x06,
        "saturation": 0x07,
        "sharpness": 0x08,
        "gamma": 0x09,
        "white_balance": 0x0A,
        "exposure_time": 0x0B,
        "focus": 0x0C,
        "zoom": 0x0D
    }
    
    try:
        # Try to detach kernel driver if it's active
        for cfg in device:
            for intf in cfg:
                if intf.bInterfaceClass == 14:  # Video class
                    if device.is_kernel_driver_active(intf.bInterfaceNumber):
                        try:
                            print(f"Detaching kernel driver from interface {intf.bInterfaceNumber}")
                            device.detach_kernel_driver(intf.bInterfaceNumber)
                        except:
                            print(f"Failed to detach kernel driver from interface {intf.bInterfaceNumber}")
                
        # Try to set configuration
        try:
            device.set_configuration()
        except:
            print("Could not set configuration (may already be configured)")
        
        # Find the video control interface
        control_interface = None
        
        for cfg in device:
            for intf in cfg:
                if intf.bInterfaceClass == 14 and intf.bInterfaceSubClass == 1:  # Video Control
                    control_interface = intf
                    break
            if control_interface:
                break
        
        if not control_interface:
            print("No video control interface found")
            return
        
        print(f"Found video control interface: {control_interface.bInterfaceNumber}")
        
        # Try all the control selectors
        results = {}
        
        for control_name, selector in controls.items():
            results[control_name] = {}
            
            # Try to get current value
            try:
                # Standard Request Format for UVC
                bmRequestType = 0xA1  # Device to Host, Class, Interface
                bRequest = UVC_GET_CUR
                wValue = (selector << 8)
                wIndex = (control_interface.bInterfaceNumber << 8)
                
                # Try with different data lengths
                for data_length in [1, 2, 4]:
                    try:
                        result = device.ctrl_transfer(bmRequestType, bRequest, wValue, wIndex, data_length)
                        if result:
                            value = 0
                            if data_length == 1:
                                value = result[0]
                            elif data_length == 2:
                                value = result[0] | (result[1] << 8)
                            elif data_length == 4:
                                value = result[0] | (result[1] << 8) | (result[2] << 16) | (result[3] << 24)
                            
                            results[control_name]["current"] = value
                            results[control_name]["data_length"] = data_length
                            break
                    except:
                        pass
                
                # If we found current value, try to get min/max
                if "current" in results[control_name]:
                    data_length = results[control_name]["data_length"]
                    
                    # Get min
                    try:
                        result = device.ctrl_transfer(bmRequestType, UVC_GET_MIN, wValue, wIndex, data_length)
                        if result:
                            value = 0
                            if data_length == 1:
                                value = result[0]
                            elif data_length == 2:
                                value = result[0] | (result[1] << 8)
                            elif data_length == 4:
                                value = result[0] | (result[1] << 8) | (result[2] << 16) | (result[3] << 24)
                            results[control_name]["min"] = value
                    except:
                        pass
                    
                    # Get max
                    try:
                        result = device.ctrl_transfer(bmRequestType, UVC_GET_MAX, wValue, wIndex, data_length)
                        if result:
                            value = 0
                            if data_length == 1:
                                value = result[0]
                            elif data_length == 2:
                                value = result[0] | (result[1] << 8)
                            elif data_length == 4:
                                value = result[0] | (result[1] << 8) | (result[2] << 16) | (result[3] << 24)
                            results[control_name]["max"] = value
                    except:
                        pass
                    
                    # Get resolution
                    try:
                        result = device.ctrl_transfer(bmRequestType, UVC_GET_RES, wValue, wIndex, data_length)
                        if result:
                            value = 0
                            if data_length == 1:
                                value = result[0]
                            elif data_length == 2:
                                value = result[0] | (result[1] << 8)
                            elif data_length == 4:
                                value = result[0] | (result[1] << 8) | (result[2] << 16) | (result[3] << 24)
                            results[control_name]["resolution"] = value
                    except:
                        pass
                    
                    # Get default
                    try:
                        result = device.ctrl_transfer(bmRequestType, UVC_GET_DEF, wValue, wIndex, data_length)
                        if result:
                            value = 0
                            if data_length == 1:
                                value = result[0]
                            elif data_length == 2:
                                value = result[0] | (result[1] << 8)
                            elif data_length == 4:
                                value = result[0] | (result[1] << 8) | (result[2] << 16) | (result[3] << 24)
                            results[control_name]["default"] = value
                    except:
                        pass
            except Exception as e:
                pass
        
        # Display results
        print("\nCamera Controls:")
        print("----------------")
        
        found_controls = False
        
        for control_name, values in results.items():
            if "current" in values:
                found_controls = True
                print(f"\n{control_name.upper()}:")
                for key, value in values.items():
                    if key != "data_length":
                        print(f"  {key}: {value}")
        
        if not found_controls:
            print("No accessible controls found.")
            print("This could be due to:")
            print("1. macOS restrictions on USB device access")
            print("2. Camera not supporting standard UVC controls")
            print("3. Need for higher privileges (try running with sudo)")
        
        # Test if we can set a control value
        print("\nTesting control write capability:")
        for control_name, values in results.items():
            if "current" in values and "min" in values and "max" in values:
                try:
                    # Choose a test value
                    current = values["current"]
                    test_value = current + 1
                    if test_value > values["max"]:
                        test_value = values["min"]
                    
                    selector = controls[control_name]
                    bmRequestType = 0x21  # Host to Device, Class, Interface
                    bRequest = 0x01  # SET_CUR
                    wValue = (selector << 8)
                    wIndex = (control_interface.bInterfaceNumber << 8)
                    
                    data_length = values["data_length"]
                    data = []
                    
                    if data_length == 1:
                        data = [test_value & 0xFF]
                    elif data_length == 2:
                        data = [test_value & 0xFF, (test_value >> 8) & 0xFF]
                    elif data_length == 4:
                        data = [test_value & 0xFF, 
                               (test_value >> 8) & 0xFF, 
                               (test_value >> 16) & 0xFF, 
                               (test_value >> 24) & 0xFF]
                    
                    result = device.ctrl_transfer(bmRequestType, bRequest, wValue, wIndex, data)
                    
                    # Read back to see if it worked
                    bmRequestType = 0xA1  # Device to Host, Class, Interface
                    bRequest = UVC_GET_CUR
                    result = device.ctrl_transfer(bmRequestType, bRequest, wValue, wIndex, data_length)
                    
                    value = 0
                    if data_length == 1:
                        value = result[0]
                    elif data_length == 2:
                        value = result[0] | (result[1] << 8)
                    elif data_length == 4:
                        value = result[0] | (result[1] << 8) | (result[2] << 16) | (result[3] << 24)
                    
                    if value == test_value:
                        print(f"{control_name}: WRITABLE (Successfully set to {test_value})")
                    else:
                        print(f"{control_name}: READ-ONLY (Got {value} instead of {test_value})")
                    
                    # Reset to original value
                    if value == test_value:
                        if data_length == 1:
                            data = [current & 0xFF]
                        elif data_length == 2:
                            data = [current & 0xFF, (current >> 8) & 0xFF]
                        elif data_length == 4:
                            data = [current & 0xFF, 
                                   (current >> 8) & 0xFF, 
                                   (current >> 16) & 0xFF, 
                                   (current >> 24) & 0xFF]
                        
                        bmRequestType = 0x21  # Host to Device, Class, Interface
                        device.ctrl_transfer(bmRequestType, 0x01, wValue, wIndex, data)
                except Exception as e:
                    print(f"{control_name}: ERROR ({str(e)})")
        
    except Exception as e:
        print(f"Error analyzing UVC controls: {e}")
    
    # Provide usage information
    print("\nUsage Instructions:")
    print("-----------------")
    print("To control this camera in your application, you'll need:")
    print(f"1. Vendor ID: {device_info['vendor_id']}")
    print(f"2. Product ID: {device_info['product_id']}")
    print("3. For each control you want to set:")
    print("   - Control selector (from the list above)")
    print("   - Data length (1, 2, or 4 bytes)")
    print("   - Min/Max values to stay within valid range")
    
    print("\nSample code to set exposure:")
    print("```python")
    print("import usb.core")
    print("import usb.util")
    print(f"dev = usb.core.find(idVendor=int({device_info['vendor_id']}, 16), idProduct=int({device_info['product_id']}, 16))")
    print("if dev is None:")
    print("    print('Device not found')")
    print("    exit()")
    print("# Set configuration")
    print("dev.set_configuration()")
    print("# Parameters for exposure control")
    print("bmRequestType = 0x21  # Host to Device, Class, Interface")
    print("bRequest = 0x01       # SET_CUR")
    print("control_selector = 0x0B  # Exposure time")
    print("interface_num = 0     # Typically the video control interface")
    print("wValue = (control_selector << 8)")
    print("wIndex = (interface_num << 8)")
    print("data_length = 4       # Usually 4 bytes for exposure")
    print("exposure_value = 500  # Adjust as needed")
    print("data = [exposure_value & 0xFF, (exposure_value >> 8) & 0xFF, (exposure_value >> 16) & 0xFF, (exposure_value >> 24) & 0xFF]")
    print("try:")
    print("    result = dev.ctrl_transfer(bmRequestType, bRequest, wValue, wIndex, data)")
    print("    print(f'Set exposure result: {result}')")
    print("except Exception as e:")
    print("    print(f'Error setting exposure: {e}')")
    print("```")

def main():
    print(f"USB Camera Diagnostic Tool for macOS ({platform.platform()})")
    print("-------------------------------------------------------")
    
    # Check if running with elevated privileges
    elevated = False
    try:
        # This would typically fail without elevated privileges
        test_dev = usb.core.find(idVendor=0x046d)  # Logitech Vendor ID
        if test_dev:
            elevated = True
    except:
        pass
    
    if not elevated and platform.system() == 'Darwin':
        print("\nWARNING: This script may need to be run with sudo on macOS")
        print("Some USB operations require elevated privileges")
        print("If you don't see your camera's controls, try: sudo python usb_camera_diag.py\n")
    
    # Find all USB devices
    all_devices = find_all_usb_devices()
    
    # Print basic info about all devices
    print("\nAll USB Devices:")
    print("--------------")
    for i, device in enumerate(all_devices):
        try:
            info = detailed_usb_device_info(device)
            print(f"Device {i+1}: {info.get('product', 'Unknown')} - {info.get('vendor_id', '?')}:{info.get('product_id', '?')}")
        except:
            print(f"Device {i+1}: [Error retrieving info]")
    
    # Find UVC cameras
    uvc_cameras = find_uvc_cameras(all_devices)
    
    if not uvc_cameras:
        print("\nNo UVC cameras found. Make sure your camera is connected.")
        print("Common issues:")
        print("1. Camera is not a standard UVC device")
        print("2. Need elevated privileges (sudo)")
        print("3. Camera is in use by another application")
        return
    
    # Print UVC camera details
    print("\nUVC Cameras:")
    print("-----------")
    for i, camera in enumerate(uvc_cameras):
        print(f"Camera {i+1}: {camera['product']} - {camera['vendor_id']}:{camera['product_id']}")
        print(f"  Manufacturer: {camera['manufacturer']}")
        print(f"  Has video control: {camera['has_video_control']}")
        print(f"  Has video streaming: {camera['has_video_streaming']}")
    
    # For each UVC camera, analyze controls
    for camera in uvc_cameras:
        analyze_uvc_controls(camera)
    
    print("\nDiagnostic complete. See above for detailed camera information.")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Error running diagnostic: {e}")
        print("\nNote: Access to USB devices on macOS may require:")
        print("1. Running with sudo privileges")
        print("2. Installing libusb: brew install libusb")
        print("3. Installing PyUSB: pip install pyusb")