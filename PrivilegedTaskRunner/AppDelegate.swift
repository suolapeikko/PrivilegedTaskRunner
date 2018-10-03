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
        
        // Create an empty authorization reference
        appVC.initAuthorizationRef()

        // Check if there's an existing PrivilegedTaskRunnerHelper already installed
        if(!appVC.checkIfHelperDaemonExists()) {
            appVC.installHelperDaemon()
        }
        else {
            // Update daemon to a newer version if client and daemon versions don't match
            self.appVC.checkHelperVersionAndUpdateIfNecessary()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {

        // Free the existing authorization reference
        appVC.freeAuthorizationRef()
    }
}
