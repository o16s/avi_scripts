import cv2
import numpy as np
import os
import time

def main():
    # Initialize camera
    print("Opening UVC fisheye camera...")
    cap = cv2.VideoCapture(1)  # Camera ID 1
    
    # Check if camera opened successfully
    if not cap.isOpened():
        print("Error: Could not open camera.")
        return
        
    # Updated checkerboard size
    checkerboard_size = (13, 9)  # Checkerboard inner corners

    # Create window
    window_name = "Fisheye Camera Focus Helper"
    cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)
    
    # Track sharpness values
    max_sharpness = 0
    max_sharpness_time = time.time()
    sharpness_history = []
    
    # Arrays to store calibration data
    objpoints = []  # 3D points in real world space
    imgpoints = []  # 2D points in image plane
    
    # Setup object points for checkerboard (0,0,0), (1,0,0), (2,0,0) ....
    objp = np.zeros((1, checkerboard_size[0]*checkerboard_size[1], 3), np.float32)
    objp[0,:,:2] = np.mgrid[0:checkerboard_size[0], 0:checkerboard_size[1]].T.reshape(-1, 2)
    
    # Create directory for calibration images
    if not os.path.exists("fisheye_calibration_images"):
        os.makedirs("fisheye_calibration_images")
    
    print("Fisheye Camera Focus Helper")
    print("---------------------------")
    print("- Manually adjust your lens while watching the sharpness value")
    print("- The focus bar will show relative sharpness (higher is better)")
    print("- Press 'r' to reset maximum sharpness")
    print("- Press 'c' to capture image for calibration")
    print("- Press 'k' to calculate FISHEYE calibration (after capturing several images)")
    print("- Press 'q' or ESC to quit")

    image_count = 0
    
    try:
        while True:
            # Capture frame
            ret, frame = cap.read()
            if not ret:
                print("Failed to grab frame - exiting")
                break
            
            # Save original frame for calibration
            original = frame.copy()
            
            # Convert to grayscale
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            
            # Find checkerboard corners
            ret, corners = cv2.findChessboardCorners(gray, checkerboard_size, 
                                                    cv2.CALIB_CB_ADAPTIVE_THRESH + 
                                                    cv2.CALIB_CB_FAST_CHECK + 
                                                    cv2.CALIB_CB_NORMALIZE_IMAGE)
            
            # Create a copy for visualization
            display_frame = frame.copy()
            
            if ret:
                # Refine corner detection
                criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.001)
                corners2 = cv2.cornerSubPix(gray, corners, (11, 11), (-1, -1), criteria)
                
                # Draw the corners
                cv2.drawChessboardCorners(display_frame, checkerboard_size, corners2, ret)
                
                # Create mask around checkerboard
                mask = np.zeros_like(gray)
                hull = cv2.convexHull(corners.astype(np.int32))
                cv2.fillConvexPoly(mask, hull, 255)
                
                # Calculate sharpness of checkerboard area
                masked_gray = cv2.bitwise_and(gray, gray, mask=mask)
                laplacian = cv2.Laplacian(masked_gray, cv2.CV_64F)
                current_sharpness = laplacian.var()
                
                # Keep history for trend line
                sharpness_history.append(current_sharpness)
                if len(sharpness_history) > 30:
                    sharpness_history.pop(0)
                
                # Update max sharpness
                if current_sharpness > max_sharpness:
                    max_sharpness = current_sharpness
                    max_sharpness_time = time.time()
                    
                # Display metrics
                cv2.putText(display_frame, f"CURRENT SHARPNESS: {current_sharpness:.2f}", 
                           (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
                cv2.putText(display_frame, f"MAX SHARPNESS: {max_sharpness:.2f}", 
                           (10, 70), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
                
                # Indicate if we're close to max sharpness
                if current_sharpness > max_sharpness * 0.95:
                    cv2.putText(display_frame, "OPTIMAL FOCUS!", 
                               (10, 110), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 255, 255), 2)
                
                # Calculate relative sharpness
                rel_sharpness = current_sharpness / max_sharpness if max_sharpness > 0 else 0
                
                # Draw focus quality bar
                bar_width = 300
                bar_height = 30
                bar_x = 10
                bar_y = display_frame.shape[0] - 60
                
                # Background bar
                cv2.rectangle(display_frame, 
                             (bar_x, bar_y), 
                             (bar_x + bar_width, bar_y + bar_height), 
                             (50, 50, 50), -1)
                
                # Fill bar based on relative sharpness
                fill_width = int(bar_width * rel_sharpness)
                
                # Color changes from red to yellow to green as sharpness improves
                if rel_sharpness < 0.7:
                    color = (0, 0, 255)  # Red
                elif rel_sharpness < 0.9:
                    color = (0, 255, 255)  # Yellow
                else:
                    color = (0, 255, 0)  # Green
                    
                cv2.rectangle(display_frame, 
                             (bar_x, bar_y), 
                             (bar_x + fill_width, bar_y + bar_height), 
                             color, -1)
                
                # Draw border
                cv2.rectangle(display_frame, 
                             (bar_x, bar_y), 
                             (bar_x + bar_width, bar_y + bar_height), 
                             (255, 255, 255), 1)
                
                # Draw scale markers
                for i in range(1, 10):
                    marker_x = bar_x + (bar_width * i) // 10
                    cv2.line(display_frame, 
                            (marker_x, bar_y), 
                            (marker_x, bar_y + 5), 
                            (255, 255, 255), 1)
                
                # Draw focus trend line
                if len(sharpness_history) > 1:
                    trend_x = display_frame.shape[1] - 120
                    trend_y = 150
                    trend_width = 100
                    trend_height = 50
                    
                    # Background
                    cv2.rectangle(display_frame, 
                                 (trend_x, trend_y), 
                                 (trend_x + trend_width, trend_y + trend_height), 
                                 (0, 0, 0), -1)
                    
                    # Normalize values for trend display
                    trend_values = sharpness_history.copy()
                    trend_max = max(trend_values)
                    if trend_max > 0:
                        trend_values = [v / trend_max * trend_height for v in trend_values]
                        
                        # Draw trend line
                        for i in range(1, len(trend_values)):
                            pt1 = (trend_x + (i-1) * trend_width // len(trend_values), 
                                  int(trend_y + trend_height - trend_values[i-1]))
                            pt2 = (trend_x + i * trend_width // len(trend_values), 
                                  int(trend_y + trend_height - trend_values[i]))
                            cv2.line(display_frame, pt1, pt2, (0, 255, 255), 1)
                    
                    # Draw border
                    cv2.rectangle(display_frame, 
                                 (trend_x, trend_y), 
                                 (trend_x + trend_width, trend_y + trend_height), 
                                 (255, 255, 255), 1)
                    
                    cv2.putText(display_frame, "Trend", 
                               (trend_x, trend_y - 5), 
                               cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)
                
            else:
                # No checkerboard detected
                cv2.putText(display_frame, "NO CHECKERBOARD DETECTED", 
                           (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2)
                cv2.putText(display_frame, "Please place the 13x9 checkerboard in view", 
                           (10, 70), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2)
            
            # Show image count
            cv2.putText(display_frame, f"CALIBRATION IMAGES: {image_count}", 
                       (10, display_frame.shape[0] - 80), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 0, 255), 2)
            cv2.putText(display_frame, "FISHEYE CAMERA MODE", 
                       (display_frame.shape[1] - 250, display_frame.shape[0] - 80), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 0, 0), 2)
            
            # Add time since max sharpness was seen
            time_since_max = time.time() - max_sharpness_time
            cv2.putText(display_frame, f"Time since max: {time_since_max:.1f}s", 
                       (display_frame.shape[1] - 200, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
            
            # Add exit instructions
            cv2.putText(display_frame, "q:quit  r:reset  c:capture  k:calibrate", 
                       (10, display_frame.shape[0] - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
            
            # Show the frame
            cv2.imshow(window_name, display_frame)
            
            # Handle key inputs with timeout to avoid blocking
            key = cv2.waitKey(1) & 0xFF
            
            # Multiple exit methods
            if key == ord('q') or key == 27:  # 'q' or ESC key
                print("Exiting program...")
                break
                
            elif key == ord('r'):  # Reset max sharpness
                max_sharpness = 0
                max_sharpness_time = time.time()
                print("Reset maximum sharpness value")
                
            elif key == ord('c'):  # Capture calibration image
                if ret:
                    image_count += 1
                    filename = f"fisheye_calibration_images/calib_{image_count}.jpg"
                    cv2.imwrite(filename, original)
                    
                    # Save the object and image points for fisheye calibration
                    if corners is not None:
                        objpoints.append(objp)
                        imgpoints.append(corners2.reshape(1, -1, 2))
                        
                        print(f"Captured fisheye calibration image {image_count}")
                    else:
                        print("Checkerboard not detected - image saved but not used for calibration")
            
            elif key == ord('k'):  # Calculate fisheye calibration
                # Calculate calibration if we have enough images
                if len(objpoints) < 5:
                    print("Need at least 5 images for calibration. Please capture more.")
                else:
                    print("\nCalculating fisheye camera calibration...")
                    
                    # Fisheye calibration needs at least 3 images
                    # Get image dimensions
                    img_shape = gray.shape[::-1]
                    
                    # Fisheye calibration requires different initialization
                    K = np.zeros((3, 3))
                    D = np.zeros((4, 1))
                    
                    # Flags for fisheye calibration
                    calibration_flags = cv2.fisheye.CALIB_RECOMPUTE_EXTRINSIC + \
                                       cv2.fisheye.CALIB_CHECK_COND + \
                                       cv2.fisheye.CALIB_FIX_SKEW
                    
                    # Perform fisheye calibration
                    try:
                        rms, K, D, rvecs, tvecs = cv2.fisheye.calibrate(
                            objpoints, imgpoints, img_shape, K, D, 
                            flags=calibration_flags)
                        
                        # Save the calibration results
                        calibration_file = "fisheye_calibration.npz"
                        np.savez(calibration_file, 
                                 camera_matrix=K,
                                 dist_coeffs=D,
                                 rvecs=rvecs,
                                 tvecs=tvecs)
                        
                        # Also save in a human-readable format
                        calibration_txt = "fisheye_calibration.txt"
                        with open(calibration_txt, 'w') as f:
                            f.write("# Fisheye Camera Calibration Results\n\n")
                            f.write(f"RMS Error: {rms}\n\n")
                            f.write("Camera Matrix (K):\n")
                            f.write(str(K))
                            f.write("\n\nDistortion Coefficients (D):\n")
                            f.write(str(D))
                        
                        print(f"Fisheye calibration complete! Saved to {calibration_file} and {calibration_txt}")
                        print(f"RMS Error: {rms}")
                        
                        # Interpret the RMS error
                        if rms < 1.0:
                            print("Excellent calibration! (RMS < 1.0)")
                        elif rms < 2.0:
                            print("Good calibration. (RMS < 2.0)")
                        elif rms < 3.0:
                            print("Acceptable calibration. (RMS < 3.0)")
                        else:
                            print("Poor calibration. Consider recapturing images. (RMS >= 3.0)")
                            
                        # Undistort a test image to show the results
                        test_img = original.copy()
                        
                        # Calculate undistortion maps
                        map1, map2 = cv2.fisheye.initUndistortRectifyMap(
                            K, D, np.eye(3), K, img_shape, cv2.CV_16SC2)
                        
                        # Apply undistortion
                        undistorted = cv2.remap(test_img, map1, map2, 
                                               interpolation=cv2.INTER_LINEAR, 
                                               borderMode=cv2.BORDER_CONSTANT)
                        
                        # Save undistorted test image
                        cv2.imwrite("fisheye_undistorted_test.jpg", undistorted)
                        print("Saved undistorted test image to 'fisheye_undistorted_test.jpg'")
                        
                        # Display the undistorted image in a new window
                        cv2.namedWindow("Undistorted Result", cv2.WINDOW_NORMAL)
                        cv2.imshow("Undistorted Result", undistorted)
                        
                    except Exception as e:
                        print(f"Calibration error: {e}")
                        print("Tips for fisheye calibration:")
                        print("- Use more images (10-20 is recommended)")
                        print("- Ensure the checkerboard fills different parts of the frame")
                        print("- Hold the checkerboard at different angles")
                        print("- Avoid having the checkerboard at the extreme edges of the fisheye view")
            
            # Check if window was closed
            if cv2.getWindowProperty(window_name, cv2.WND_PROP_VISIBLE) < 1:
                print("Window closed - exiting")
                break
    
    except KeyboardInterrupt:
        print("Interrupted by user - exiting")
    except Exception as e:
        print(f"Error: {e}")
    finally:
        # Always clean up resources properly
        print("Cleaning up resources...")
        cap.release()
        cv2.destroyAllWindows()
        print("Exit successful!")

if __name__ == "__main__":
    main()