//
//  AppDelegate.swift
//  PrivilegedTaskRunner
//
//  Created by Suolapeikko
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var appVC: AppViewController!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
    
        appVC.installHelperDaemon()
        
        // Check for existing helper daemon and install it if it does not exist
        if(!appVC.checkIfHelperDaemonExists()) {
            appVC.installHelperDaemon()
        }
        else { // If it is freshly installed, no need to check version discrepancies
            // Update daemon to a newer version if client and daemon versions don't match
            appVC.checkHelperVersionAndUpdateIfNecessary()
        }
        
        // Create an empty authorization reference
        appVC.initAuthorizationRef()
    }

    func applicationWillTerminate(_ aNotification: Notification) {

        // Free the existing authorization reference
        appVC.freeAuthorizationRef()
    }
}
