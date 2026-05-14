# KSMacExplorer 🗂️
**Ultimate Mac File Explorer / จัดการไฟล์บน Mac**

![Version](https://img.shields.io/badge/version-1.0-blue.svg)
![macOS](https://img.shields.io/badge/macOS-12.0%2B-success.svg)
![SwiftUI](https://img.shields.io/badge/SwiftUI_&_AppKit-Native-orange.svg)
![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)

**[EN]** A Mac File Manager familiar to Windows users, with its entire code and structure built by AI. Built entirely with Swift, SwiftUI and AppKit for blazing-fast speed and low memory footprint.

**[TH]** แอปพลิเคชัน File Manager บน Mac ที่ผู้ใช้ Windows อาจคุ้นเคย โค้ดและโครงสร้างทั้งหมดถูกสร้างขึ้นด้วยพลังของ AI ผสานกับ SwiftUI และ AppKit 100%

---

## ⬇️ Download / ดาวน์โหลด

**[EN]** You can download the latest version of the installer (`.dmg`) from our **Releases** page:
* 🔗 [Download KSMacExplorer (Latest Release)](https://github.com/ksplayfoft/ksmacexplorer/releases/latest)

**[TH]** คุณสามารถดาวน์โหลดตัวติดตั้งเวอร์ชันล่าสุด (`.dmg`) ได้ที่หน้า **Releases**:
* 🔗 [ดาวน์โหลด KSMacExplorer (เวอร์ชันล่าสุด)](https://github.com/ksplayfoft/ksmacexplorer/releases/latest)

---

## ✨ Key Features / คุณสมบัติเด่น

* **⚡ Native Performance:** Built entirely with Swift, SwiftUI and AppKit for blazing-fast speed and low memory footprint. (พัฒนาด้วยภาษา Swift SwiftUI และ AppKit เพื่อให้แอปทำงานได้รวดเร็วและลื่นไหล)
* **🖱️ Cross-App Drag & Drop:** Drag and drop files across different applications with copy and move logic. (รองรับการลากและวางไฟล์ข้ามแอปพลิเคชัน พร้อมระบบ Copy/Move)
* **🗂️ Rich File Operations:** Full support for copy, cut, paste, zip compression, and unzipping directly from the app interface. (ระบบจัดการไฟล์ Cut, Copy, Paste และการบีบอัด/แตกไฟล์ (Zip/Unzip))
* **👁️ Dual View Modes:** Switch between Icon View and List View to match your personal workflow. (เลือกมุมมองเปลี่ยนไปมาระหว่าง Icon View และ List View)
* **🧭 Smart Sidebar:** Quickly access your home folders, external drives, and Cloud Drive (including Google Drive). (เข้าถึงโฟลเดอร์สำคัญ, External Drive และ Cloud Drive)
* **🤖 AI-Generated Code:** The architecture and source code of this application were crafted entirely using advanced AI technology. (โปรแกรมนี้ถูกออกแบบโครงสร้างและเขียนซอร์สโค้ดทั้งหมดด้วยเทคโนโลยี AI)

---

## 🛠 Installation & Setup Guide / การติดตั้งและการตั้งค่าที่สำคัญ

### 1. Opening the App for the First Time (Gatekeeper) / การเปิดแอปครั้งแรก
Because the app is not distributed via the Mac App Store, macOS might block it initially. You can bypass this in three ways: 
*(เนื่องจากแอปไม่ได้แจกจ่ายผ่าน App Store ระบบ macOS อาจบล็อกและแจ้งเตือนเมื่อเปิดใช้งานครั้งแรก คุณสามารถแก้ไขได้ 3 วิธี:)*

* **Method 1:** Right-click the KSMacExplorer icon and select **Open**, then confirm. *(คลิกขวาที่ไอคอนแอป แล้วเลือก **Open (เปิด)** จากนั้นกดยืนยัน)*
* **Method 2:** Go to **System Settings** > **Privacy & Security**, scroll down to the Security section, and click **Open Anyway** to allow the app to run. *(ไปที่ **System Settings** > **Privacy & Security** เลื่อนลงมาที่หัวข้อ Security แล้วคลิกปุ่ม **Open Anyway (อนุญาตต่อไป)**)*
* **Method 3:** Open the Terminal app and run this command to remove the quarantine flag: *(เปิดแอป Terminal ใน Mac แล้วคัดลอกคำสั่งด้านล่างนี้ไปรัน:)*
    ```bash
    xattr -cr /Applications/KSMacExplorer.app
    ```

### 2. Granting Full Disk Access / การอนุญาตให้จัดการไฟล์
To allow the app to fully manage files across your system, you need to grant it Full Disk Access:
*(เพื่อให้ KSMacExplorer สามารถเข้าถึงและจัดการไฟล์ได้ครอบคลุมทุกโฟลเดอร์ในเครื่อง กรุณาตั้งค่าตามนี้:)*

1. Go to **System Settings** > **Privacy & Security**. (ไปที่ **System Settings** > **Privacy & Security**)
2. Scroll down and select **Full Disk Access**. (คลิกที่เมนู **Full Disk Access**)
3. Toggle the switch on for **KSMacExplorer**. (เปิดสวิตช์ด้านหลังแอป **KSMacExplorer**)
> *If KSMacExplorer is not listed, click the **+** button at the bottom to add it manually.*
> *(หากไม่พบแอปในรายการ ให้กดปุ่ม **+** ด้านล่าง แล้วเลือกแอป KSMacExplorer เข้าไป)*

---

## 👨‍💻 Developer / ผู้พัฒนา

**Developed by KS**  
Independent developer utilizing the power of AI to create useful and powerful tools for macOS.  
*(นักพัฒนาแอปพลิเคชันอิสระ ผู้ประยุกต์ใช้พลังของ AI ในการสร้างเครื่องมือที่มีประโยชน์และทรงพลังบน macOS)*

---

## ⚠️ Disclaimer / ข้อสงวนสิทธิ์ในการรับผิดชอบ

**[EN]** This software is provided "as is", without warranty of any kind, express or implied. The developer makes no guarantees regarding the accuracy, reliability, or completeness of the software. In no event shall the developer be liable for any claim, damages, data loss, file corruption, or other liability arising from the use of this software. You use this file management application entirely at your own risk. Please ensure you have backups of your important data.

**[TH]** ซอฟต์แวร์นี้ถูกจัดเตรียมให้ "ตามสภาพ" (As is) โดยไม่มีการรับประกันใดๆ ทั้งสิ้น ไม่ว่าโดยชัดแจ้งหรือโดยนัย ผู้พัฒนาไม่รับรองความถูกต้อง ความน่าเชื่อถือ หรือความสมบูรณ์ของซอฟต์แวร์นี้ ผู้พัฒนาจะไม่รับผิดชอบต่อความเสียหายใดๆ การสูญหายของข้อมูล ไฟล์เสียหาย หรือปัญหาใดๆ ที่เกิดขึ้นจากการใช้งานแอปพลิเคชันจัดการไฟล์นี้ ผู้ใช้ต้องยอมรับความเสี่ยงในการใช้งานด้วยตนเองทั้งหมด กรุณาสำรองข้อมูล (Backup) ที่สำคัญของท่านอยู่เสมอ

---

## 📄 License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**. 

You may copy, distribute and modify the software as long as you track changes/dates in source files. Any modifications to or software including (via compiler) GPL-licensed code must also be made available under the GPL along with build & install instructions.

See the `LICENSE` file for more details.
