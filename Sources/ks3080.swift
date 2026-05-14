/*
 ks3080 - macOS Battery Monitor
 Copyright (C) 2026 KS (or current year/author)

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import IOKit.ps
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem?
    var timer: Timer?
    var lastNotifiedLevel: Int?
    
    // 1. เพิ่มตัวแปรเช็คสถานะว่าพักการแจ้งเตือนอยู่หรือไม่
    var isPaused: Bool = false
    // 2. เก็บ Reference ของ Menu Item เพื่อเอาไว้เปลี่ยนชื่อ (Pause <-> Resume)
    var pauseResumeMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "--%" 
        }

        let menu = NSMenu()
        
        // --- ส่วนที่เพิ่มใหม่: เมนู About ---
        menu.addItem(NSMenuItem(title: "About ks3080", action: #selector(showAboutWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        // -----------------------------
        
        // 3. เพิ่มเมนู Pause / Resume
        pauseResumeMenuItem = NSMenuItem(title: "Pause Notifications", action: #selector(togglePauseResume), keyEquivalent: "p")
        menu.addItem(pauseResumeMenuItem)
        
        // เพิ่มเส้นคั่นเมนูให้ดูสวยงาม
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Exit ks3080", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu

        requestNotificationPermission()

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            self.updateBatteryStatus()
        }
        
        updateBatteryStatus()
    }
    
    // --- ฟังก์ชันแสดงหน้าต่าง About ---
    @objc func showAboutWindow() {
        // บังคับให้แอปของเราดึงตัวเองขึ้นมาอยู่ด้านหน้าสุดก่อนแสดงหน้าต่าง
        NSApp.activate(ignoringOtherApps: true)
        
        let alert = NSAlert()
        alert.messageText = "About ks3080"
        
        // ระบุข้อมูล License และการปฏิเสธความรับผิดชอบ (Disclaimer) ตามข้อกำหนด GPLv3
        alert.informativeText = """
        Version 1.0
        Copyright © 2026 KS. All rights reserved.

        This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

        DISCLAIMER:
        This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
        """
        
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        
        // ถ้าต้องการเพิ่มปุ่มสำหรับเปิดหน้าเว็บ License ก็ทำได้
        alert.addButton(withTitle: "View License")
        
        let response = alert.runModal()
        
        // ตรวจสอบว่าผู้ใช้กดปุ่ม "View License" (ปุ่มที่ 2) หรือไม่
        if response == .alertSecondButtonReturn {
            if let url = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // 4. ฟังก์ชันสำหรับสลับสถานะ Pause/Resume
    @objc func togglePauseResume() {
        isPaused.toggle() // สลับค่า true/false
        
        if isPaused {
            pauseResumeMenuItem.title = "Resume Notifications"
        } else {
            pauseResumeMenuItem.title = "Pause Notifications"
        }
        
        // สั่งอัปเดต UI ทันทีเพื่อให้สัญลักษณ์บน Menu Bar เปลี่ยน
        updateBatteryStatus()
    }

    func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Permission granted!")
                
                // หน่วงเวลา 1.5 วินาที เพื่อให้ระบบลงทะเบียนแอปเสร็จสมบูรณ์ก่อนเด้ง Noti
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.sendImmediateTestNotification()
                }
            } else {
                print("Permission denied: \(String(describing: error))")
            }
        }
    }

    func sendImmediateTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "ks3080 Ready!"
        content.body = "The system will monitor battery levels at 10%, 20%, 30%, 80%, 90%, and 100%."
        content.sound = .default

        // ใช้ UUID เพื่อสร้าง ID ไม่ซ้ำกัน (ป้องกัน OS มองว่าเป็นข้อความขยะ/ข้อความซ้ำ)
        let uniqueID = "test-notification-\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: uniqueID, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error adding notification: \(error)")
            } else {
                print("Test Notification scheduled successfully!")
            }
        }
    }

    @objc func updateBatteryStatus() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as Array<CFTypeRef>? else { return }
        
        for source in sources {
            if let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
               let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int,
               let maxCapacity = description[kIOPSMaxCapacityKey] as? Int {
                
                let batteryLevel = Int(Double(currentCapacity) / Double(maxCapacity) * 100)
                
                DispatchQueue.main.async {
                    // 5. แสดงสัญลักษณ์ ⏸ บน Menu Bar ถ้าถูก Pause ไว้
                    let pauseIcon = self.isPaused ? " ⏸" : ""
                    self.statusItem?.button?.title = "\(batteryLevel)%\(pauseIcon)"
                }

                // Logic: เช็คว่าตัวเลขตรงกับเป้าหมายไหม
                if (batteryLevel == 10 || batteryLevel == 20 || batteryLevel == 30 || batteryLevel == 80 || batteryLevel == 90 || batteryLevel == 100) {
                    if lastNotifiedLevel != batteryLevel {
                        // 6. ส่งการแจ้งเตือนก็ต่อเมื่อไม่ได้กด Pause ไว้เท่านั้น
                        if !isPaused {
                            sendBatteryNotification(level: batteryLevel)
                        }
                        // บันทึกค่าว่าเจอกับเลขนี้แล้ว (แม้จะ Pause อยู่ก็ตาม เพื่อไม่ให้พอกด Resume แล้วมันเด้งย้อนหลัง)
                        lastNotifiedLevel = batteryLevel
                    }
                } else {
                    lastNotifiedLevel = nil
                }
            }
        }
    }

    func sendBatteryNotification(level: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Battery Alert: \(level)%"
        
        if level <= 30 {
            content.body = "The battery is at \(level)%. Please plug in your charger."
        } else if level >= 80 {
            content.body = "The battery is at \(level)%. Please unplug your charger."
        } else {
            content.body = "The battery is currently at level \(level)%."
        }
        
        content.sound = .default

        let request = UNNotificationRequest(identifier: "battery-alert-\(level)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

// --- Main Entry Point ---
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()