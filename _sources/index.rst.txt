Anisca Vision OpenWRT Camera User Manual
=========================================

.. toctree::
   :maxdepth: 3
   :caption: Contents:

   intended-use
   quick-start
   accessing-camera
   live-view
   camera-configuration
   azure-storage
   s3-storage
   privacy-polygon
   additional-settings
   software-updates
   security
   technical-specs
   troubleshooting
   support

Intended Use
============

The Anisca Vision OpenWRT Camera is a specialized, local first, surveillance device designed for automated monitoring and analytics. The camera:

* **Automatically captures and uploads** snapshots to Microsoft Azure Blob Storage at configurable intervals
* **Provides real-time monitoring** via web interface live view
* **Operates autonomously** once configured - no manual intervention required
* **Extracts simple local analytics** like motion in a ROI and color/brightness metrics

More use cases are possible after setup of the optional cloud connection:

* **AI Data Analytics** from uploaded images including:
  
  - People counting and occupancy monitoring
  - Brightness and lighting condition analysis  
  - Change detection and motion analysis
  - Environmental monitoring
  
* **Timelapses** from continuous image sequences

Primary Applications
--------------------

* Retail analytics (customer counting, dwell time)
* Office occupancy monitoring  
* Construction site progress documentation
* Environmental monitoring (weather, lighting changes)
* Security and surveillance with historical data
* Traffic and pedestrian flow analysis

The camera is designed as a "set and forget" solution - configure once, then let it continuously collect visual data for your analytics needs.

Quick Start
===========

What You Need
-------------

* PoE switch supporting up to 13W per port (or 5V USB power for WiFi only models)
* Ethernet cable with supplied rubber grommet (PoE models)
* Microsoft Azure account with Blob Storage

Installation
------------

1. Connect camera to PoE switch using supplied ethernet cable (or USB power for WiFi models)
2. **Important:** Use the rubber grommet to protect ethernet connection from moisture (PoE models)
3. Camera will automatically get IP address via DHCP
4. Hostname will be the camera's serial number (e.g., ``e438191ae89e``)

.. warning::
   Always use the supplied rubber grommet for moisture protection, especially outdoors.

Accessing the Camera Web Interface
===================================

Changing the Default Password
-----------------------------

Method 1 - With DHCP (Recommended)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

1. Check your router's web interface for connected devices
2. Look for device with hostname matching camera serial number (e.g., ``e438191ae89e``)
3. Open web browser and navigate to that IP address
4. Login with username ``root`` and default password ``e438191ae89e``. 
5. Change the password under  **System** → **Administration** in the top menu.

Method 2 - Without DHCP (Direct Connection)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

1. Set your computer IP to ``192.168.123.251``
2. Set subnet mask to ``255.255.255.0``
3. Leave gateway and DNS empty
4. Navigate to ``192.168.123.250`` in web browser
5. Login with username ``root`` and default password ``e438191ae89e``. 
6. Change the password under  **System** → **Administration** in the top menu.

Multiple Camera Warning
-----------------------

.. danger::
   **Multiple Camera Warning:** ALL cameras use the same default IP address ``192.168.123.250``. If you have multiple cameras on the same network:
   
   * **Option 1:** Use DHCP (recommended) - each camera gets unique IP automatically
   * **Option 2:** Configure manually by turning cameras on **one at a time**, setting unique static IPs for each

   Never power on multiple unconfigured cameras simultaneously on the same network!

.. note::
   The camera runs OpenWRT (Version 22+) firmware with LuCI web interface and customised camera software. It is straightforward to install your own software and scripts via SSH using the command ``opkg install``.

Live View
=========

Viewing the Live Feed
--------------------

To view the camera's live feed:

1. Open camera web interface in your browser
2. Click **Services** → **Camera** in the top menu
3. Live video stream will display automatically
4. Use this to verify camera positioning and image quality

Stream Information
------------------

* Live stream URL: ``http://camera-ip:8080/?action=stream``
* Snapshot URL: ``http://camera-ip:8080/?action=snapshot``
* Stream runs on port 8080

.. tip::
   Use Chrome or Firefox browsers for best compatibility.

Camera Configuration
====================

Access camera settings via **Services** → **Camera** → **⚙️ Camera Settings**

Upload Settings
---------------

**Upload Interval:** Configure how often images are uploaded (5-3600 seconds)

* Default: 60 seconds
* Quick presets: 10s, 30s, 1min, 5min, 10min
* Lower intervals = more frequent uploads = higher bandwidth usage

Camera Controls
---------------

The camera provides extensive image quality controls:

.. list-table:: Camera Hardware Controls
   :widths: 30 20 50
   :header-rows: 1

   * - Setting
     - Range
     - Description
   * - Brightness
     - -64 to 64
     - Overall image brightness
   * - Contrast
     - 0 to 64
     - Image contrast level
   * - Saturation
     - 0 to 128
     - Color saturation intensity
   * - Hue
     - -40 to 40
     - Color hue adjustment
   * - Gamma
     - 72 to 500
     - Gamma correction
   * - Gain
     - 0 to 100
     - Image sensor gain
   * - Sharpness
     - 0 to 6
     - Image sharpness level
   * - Backlight Compensation
     - 0 to 2
     - Compensation for backlighting

Additional Controls
~~~~~~~~~~~~~~~~~~~

* **Auto White Balance:** Automatic color temperature adjustment
* **Auto Exposure Priority:** Automatic exposure control

Azure Storage Configuration
===========================

Configure Azure Blob Storage for automatic uploads to a container:

Required Information
--------------------

1. **Storage Account Name:** Your Azure storage account name
2. **Container Name:** Target container within storage account  
3. **SAS Token:** Shared Access Signature token with write permissions

Setup Steps
-----------

1. In camera web interface, go to **Services** → **Camera** → **⚙️ Camera Settings**
2. Scroll to **🗄️ Azure Storage Settings**
3. Fill in the three required fields:

   * **Storage Account Name:** ``yourstorageaccount``
   * **Container Name:** ``your-container``
   * **SAS Token:** ``?sv=2023-01-03&st=...`` (include the leading ``?``)

4. Save settings

Getting Azure SAS Token
------------------------

1. Log into Azure Portal
2. Go to your Storage Account
3. Navigate to **Security + networking** → **Shared access signature**
4. Configure permissions:

   * **Allowed services:** Blob
   * **Allowed resource types:** Container, Object
   * **Allowed permissions:** Write
   * **Start/End time:** Set appropriate validity period

5. Generate SAS token and copy the complete token (including ``?``)

.. warning::
   Keep your SAS token secure. Set appropriate expiration dates and minimal required permissions.

S3 Storage Configuration
========================

.. note::
   Currently S3 storage is not supported.

Privacy Polygon Configuration
=============================

The privacy polygon feature allows you to blackout specific areas of the camera image for privacy protection.

Step-by-Step Setup
------------------

Install Camera in Final Position
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Mount the camera in its final installation location and ensure it's properly positioned.

Capture Reference Image
~~~~~~~~~~~~~~~~~~~~~~~

* Open camera web interface and go to **Services** → **Camera**
* View the live stream to see the current camera view
* Right-click on the live image and select **"Save image as"** or take a screenshot
* Save the image to your computer

Create Polygon Coordinates
~~~~~~~~~~~~~~~~~~~~~~~~~~~

* Open https://www.image-map.net/ in your web browser
* Upload your saved camera image to the website
* Select **"Polygon"** tool from the toolbar
* Click around the area you want to blackout to create a polygon shape
* The website will automatically generate coordinate values

Copy Coordinates to Camera
~~~~~~~~~~~~~~~~~~~~~~~~~~~

* Copy the generated coordinates from image-map.net
* Return to camera web interface **Services** → **Camera** → **⚙️ Camera Settings**
* Scroll to **🔒 Privacy Settings**
* Paste coordinates into **Privacy Polygon** field
* Format should be: ``x1,y1 x2,y2 x3,y3 x4,y4``
* Save settings

Example Usage
-------------

If you want to blackout a rectangular area, coordinates might look like:
``100,100 200,100 200,200 100,200``

Tips and Notes
--------------

* You can create multiple polygons by adding more coordinate pairs
* Test the privacy mask by viewing the live stream after saving settings
* Leave the field empty to disable privacy masking
* Coordinates are relative to the camera's image resolution

Additional Settings
===================

Customer and Camera Information
-------------------------------

* **Customer Name:** Identifier for your organization. This is the folder name of all the snapshots of this camera in the Azure Blob Storage container.
* **Camera Name:** Unique identifier for this camera (defaults to serial number). This is the folder name of the camera and filename of the latest snapshot of this camera.

Audio Settings
--------------

* **Enable Audio Recording:** Toggle audio capture on/off
* **Audio Duration:** Length of audio clips (seconds)

.. note::
   Audio recording is disabled by default and may not be available on all models.

Monitoring
----------

If you would like your camera to ping a remote URL (like Uptime Kuma's "push monitor"), you can set the following parameters:

* **Uptime API URL:** For external monitoring services
* **Uptime Ping URL:** Health check endpoint

Version Information
-------------------

The camera settings page displays current software version information:

* **AVI Scripts Version:** Current installed version
* **Last Updated:** When the scripts were last updated
* **Commit Hash:** Git commit hash of current installation

This information is automatically updated when running the install script.

User Manual Access
------------------

* **Documentation:** Link to latest user manual and documentation
* **Support:** Contact information and support resources

Software Updates
=================

OpenWRT Firmware Update
-----------------------

Download Latest Firmware
~~~~~~~~~~~~~~~~~~~~~~~~~

* Visit https://www.octanis.ch/anisca-vision-openwrt-camera
* Download the latest firmware image file (``.bin`` format)
* Save to your computer

Access Flash Firmware Interface
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

* Open camera web interface
* Navigate to **System** → **Backup / Flash Firmware**
* Click on **"Flash new firmware image"** section

Upload and Verify Firmware
~~~~~~~~~~~~~~~~~~~~~~~~~~~

* Click **"Choose File"** and select downloaded firmware image
* Click **"Upload"** to upload the firmware
* Click **"Verify"** to check firmware integrity

Flash Firmware
~~~~~~~~~~~~~~

* After successful verification, click **"Proceed"** to flash firmware
* **DO NOT TURN OFF THE CAMERA OR UNPLUG ETHERNET CABLE**
* Wait for the flashing process to complete (usually 2-5 minutes)
* Camera will automatically reboot

Update Camera Scripts
~~~~~~~~~~~~~~~~~~~~~

After firmware update, you need to update the camera application scripts:

* Connect to camera via SSH: ``ssh root@camera-ip``
* Run the install script: ``curl -fsSL "https://install.anisca.io?$(date +%s)" | sh``
* This updates all camera-specific software and version information

.. danger::
   **Critical Warning:** Never disconnect power or ethernet during firmware update. This will permanently damage the camera requiring factory repair.

AVI Scripts Update
------------------

To update only the camera application scripts (without changing OpenWRT):

1. Connect to camera via SSH: ``ssh root@camera-ip``
2. Run: ``curl -fsSL "https://install.anisca.io?$(date +%s)" | sh``
3. The script will update all components and version information automatically

For more information, see: https://github.com/o16s/avi_scripts

Security
========

Defense in Depth Security
-------------------------

To ensure secure operation of your camera, implement these essential security measures:

Password Security
-----------------

Change Default Password Immediately
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

1. Navigate to **System** → **Administration** in the web interface
2. Change the default password to a strong, unique password
3. Use at least 12 characters with mix of letters, numbers, and symbols
4. Save the new password securely

.. danger::
   Never leave the camera with default credentials. This is a critical security vulnerability.

Network Access Control
----------------------

Block All Internet Access Except Azure
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The camera should only communicate with Microsoft Azure services, if the cloud connectivity is desired. Configure your firewall/router to:

**Only allow outbound connections to:**

* ``*.blob.core.windows.net`` (Azure Blob Storage)
* ``*.core.windows.net`` (Azure endpoints)
* Port 443 (HTTPS) for secure uploads

Router/Firewall Configuration
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

1. Create a dedicated VLAN for IoT devices including the camera
2. Apply strict egress filtering allowing only Azure domains
3. Block all other outbound internet traffic from camera IP

**Example firewall rules:**
::

    # Allow Azure Blob Storage
    ALLOW camera_ip -> *.blob.core.windows.net:443
    ALLOW camera_ip -> *.core.windows.net:443
    
    # Block all other internet access
    DENY camera_ip -> * (internet)
    
    # Allow local network access for management
    ALLOW local_network -> camera_ip:80

Network Segmentation
~~~~~~~~~~~~~~~~~~~~

* Place camera on isolated network segment
* Restrict access to management interface to specific admin IPs
* Monitor network traffic for unexpected connections

Additional Security Measures
----------------------------

1. **Regular Updates:** Keep firmware updated via **System** → **Software**
2. **Access Logging:** Monitor who accesses the camera web interface
3. **Physical Security:** Secure camera mounting location
4. **Backup Configuration:** Save camera settings after configuration

Why These Measures Matter
-------------------------

Password Protection
~~~~~~~~~~~~~~~~~~~

* Prevents unauthorized access to camera controls
* Stops malicious configuration changes
* Protects your Azure credentials stored in the device

Network Restrictions
~~~~~~~~~~~~~~~~~~~~

* Prevents camera from being used in botnet attacks
* Blocks data exfiltration to unauthorized services
* Reduces attack surface by limiting accessible services
* Ensures data only goes to your intended Azure storage

Technical Specifications
========================

System Specifications
---------------------

.. list-table::
   :widths: 40 60

   * - Model
     - AVI-1-1
   * - Architecture
     - MediaTek MT7628AN
   * - CPU
     - ramips/mt76x8
   * - Firmware
     - OpenWrt 22+
   * - Power Consumption
     - 14.0W
   * - Network Interface
     - PoE variant: 100Mb Ethernet / WiFi variant: 802.11bgn WiFi
   * - Operating Temperature
     - 0°C to 50°C
   * - Upload Interval
     - 5-3600 seconds (configurable)

Camera Variants
---------------

.. list-table::
   :widths: 30 30 30
   :header-rows: 1

   * - Specification
     - 1MP Model
     - 2MP Model
   * - **Resolution**
     - 1280×720 (HD)
     - 1600×1200 (UXGA)
   * - **Frame Rate**
     - 30fps max

Common Features
---------------

**Both models feature:**

* 120° wide-angle lens for broad coverage
* PoE power (IEEE 802.3at) or 5V USB
* Configurable image quality controls
* Weather-resistant housing (IP65 when properly installed)

Troubleshooting
===============

Web Interface Access Issues
---------------------------

Cannot Access Web Interface
~~~~~~~~~~~~~~~~~~~~~~~~~~~

* Verify PoE switch shows power indicator for camera port
* Check ethernet cable connection
* Try accessing default IP: ``192.168.123.250``
* **For multiple cameras:** Ensure only one camera is powered on, or use DHCP
* Ensure computer and camera are on same network

Video Stream Issues
-------------------

No Live Video Stream
~~~~~~~~~~~~~~~~~~~~

* Use Chrome or Firefox browser (Safari may have issues)
* Check that port 8080 is accessible
* Check network bandwidth and stability
* Restart camera via web interface **System** → **Reboot**
* Verify camera lens is not obstructed

Azure Upload Issues
-------------------

Azure Upload Not Working
~~~~~~~~~~~~~~~~~~~~~~~~

* Verify all three Azure fields are filled correctly:

  - Storage Account Name (no special characters)
  - Container Name (must exist in storage account)
  - SAS Token (include leading ``?``, check expiration date)

* Check internet connectivity from camera's network
* Confirm Azure storage account is active and accessible
* **Check firewall rules** - ensure Azure domains are allowed
* Review upload interval setting (minimum 10 seconds)

Image Quality Issues
--------------------

Poor Image Quality
~~~~~~~~~~~~~~~~~~

* Clean camera lens with soft, lint-free cloth
* Adjust camera controls: brightness, contrast, saturation
* Check lighting conditions and backlight compensation setting
* Verify camera is properly focused (fixed focus lens)

Network Configuration Issues
----------------------------

Multiple Cameras on Same Network
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

* Use DHCP for automatic IP assignment (recommended)
* OR configure cameras sequentially with static IPs
* Never power multiple unconfigured cameras simultaneously

Factory Reset
-------------

If camera becomes unresponsive:

1. Locate small reset button on camera housing
2. Press and hold reset button for 10 seconds while camera is powered
3. Release button and wait for camera to reboot (about 2 minutes)
4. Camera will return to default settings
5. **Remember to reconfigure all settings after reset**

Support & Warranty
==================

Technical Support
-----------------

* Email: support@octanis.ch
* Website: https://www.octanis.ch/en/anisca-vision-openwrt-camera

Warranty Information
-------------------

* 2 years from purchase date
* Covers manufacturing defects
* Excludes damage from misuse or environmental factors