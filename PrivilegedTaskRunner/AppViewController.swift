//
//  AppViewController.swift
//  PrivilegedTaskRunner
//
//  Created by Suolapeikko
//

import Foundation
import Cocoa
import Security
import ServiceManagement

class AppViewController: NSViewController {
    
    @IBOutlet weak var runButton: NSButton!
    @IBOutlet weak var clearButton: NSButton!
    @IBOutlet weak var clearDBButton: NSButton!
    @IBOutlet weak var stepperControl: NSStepper!
    @IBOutlet weak var stepperValue: NSTextField!
    @IBOutlet weak var requireAuthenticationCheck: NSButton!
    @IBOutlet weak var commandField: NSTextField!
    @IBOutlet weak var outputField: NSTextField!
    
    var connection: NSXPCConnection?
    var authRef: AuthorizationRef?

    /// Initialize AuthorizationRef, as we need to manage it's lifecycle
    func initAuthorizationRef() {
    
        // Create an empty AuthorizationRef
        let status = AuthorizationCreate(nil, nil, AuthorizationFlags(), &authRef)
        if (status != OSStatus(errAuthorizationSuccess)) {
            NSLog("AppviewController: AuthorizationCreate failed")
            return
        }
    }

    /// Free AuthorizationRef, as we need to manage it's lifecycle
    func freeAuthorizationRef() {
        
        AuthorizationFree(authRef!, AuthorizationFlags.destroyRights)
    }

    /// Send user specified command to helper procecss
    ///
    /// - parameters:
    ///   - NSButton: sender
    @IBAction func clearSecurityDBButtonClicked(sender: NSButton) {
        
        stepperControl.isEnabled = true
        
        // Remove this app's specific authorization information from the security database
        NSLog("AppviewController: AuthorizationRightRemove")

        let status = AuthorizationRightRemove(authRef!, AppAuthorizationRights.shellRightName.utf8String!)
        
        if(status == errAuthorizationSuccess) {
            NSLog("AppviewController: AuthorizationRightRemove was successful")
        }
        else {
            NSLog("AppviewController: AuthorizationRightRemove failed")
        }

        clearDBButton.isEnabled = false
    }
    
    /// Modify timeout stepper value
    ///
    /// - parameters:
    ///   - NSButton: sender
    @IBAction func bumpValueClicked(sender: NSStepper) {

        stepperValue.intValue = sender.intValue
    }
    
    /// Send user specified command to helper procecss
    ///
    /// - parameters:
    ///   - NSButton: sender
    @IBAction func runButtonClicked(sender: NSButton) {
        
        // Lock stepper so that user is not able to change timeout value until security database is cleared
        stepperControl.isEnabled = false
        
        // Enable user to clear the security database as this method adds app privileges
        clearDBButton.isEnabled = true
        
        // Just to demonstrate that both end up with that command to be run as the helper runs as root
        if(requireAuthenticationCheck.state.rawValue == 1) {
            callHelperWithAuthorization()
        }
        else {
            callHelperWithoutAuthorization()
        }
    }

    /// Clear output field
    ///
    /// - parameters:
    ///   - NSButton: sender
    @IBAction func clearButtonClicked(sender: NSButton) {

        self.outputField.stringValue = ">_"
    }
    
    /// Call Helper using XPC without authorization
    func callHelperWithoutAuthorization() {
        
        // When the connection is valid, do the actual inter process call
        let xpcService = prepareXPC()?.remoteObjectProxyWithErrorHandler() { error -> Void in
            NSLog("AppviewController: XPC error: \(error)")
            } as? RemoteProcessProtocol
        
        xpcService?.runCommand(path: commandField.stringValue, reply: {
            reply in
                // Let's update GUI asynchronously
                DispatchQueue.global(qos: .background).async {
                    // Background Thread
                    DispatchQueue.main.async {
                    // Run UI Updates
                        self.outputField.stringValue += "ls /var/db/sudo\n" + reply + "\n>_"
                    }
                }
        })
    }
    
    /// Call Helper using XPC with authorization
    func callHelperWithAuthorization() {
        
        var authRefExtForm = AuthorizationExternalForm()
        let timeout = stepperValue.intValue
        
        // Make an external form of the AuthorizationRef
        var status = AuthorizationMakeExternalForm(authRef!, &authRefExtForm)
        if (status != OSStatus(errAuthorizationSuccess)) {
            NSLog("AppviewController: AuthorizationMakeExternalForm failed")
            return
        }
        
        // Add all or update required authorization right definition to the authorization database
        var currentRight:CFDictionary?
        
        // Try to get the authorization right definition from the database
        status = AuthorizationRightGet(AppAuthorizationRights.shellRightName.utf8String!, &currentRight)
        
        if (status == errAuthorizationDenied) {
            
            var defaultRules = AppAuthorizationRights.shellRightDefaultRule
            defaultRules.updateValue(timeout as AnyObject, forKey: "timeout")
            status = AuthorizationRightSet(authRef!, AppAuthorizationRights.shellRightName.utf8String!, defaultRules as CFDictionary, AppAuthorizationRights.shellRightDescription, nil, "Common" as CFString)
            NSLog("AppviewController: : Adding authorization right to the security database")
        }
        
        // We need to put the AuthorizationRef to a form that can be passed through inter process call
        let authData = NSData.init(bytes: &authRefExtForm, length:kAuthorizationExternalFormLength)
        
        // When the connection is valid, do the actual inter process call
        let xpcService = prepareXPC()?.remoteObjectProxyWithErrorHandler() { error -> Void in
            NSLog("AppviewController: XPC error: \(error)")
            } as? RemoteProcessProtocol
        
        xpcService?.runCommand(path: commandField.stringValue, authData: authData, reply: {
            reply in
            // Let's update GUI asynchronously
            DispatchQueue.global(qos: .background).async {
                // Background Thread
                DispatchQueue.main.async {
                    // Run UI Updates
                    self.outputField.stringValue += "ls /var/db/sudo\n" + reply + "\n>_"
                }
            }
        })
    }

    /// Prepare XPC connection for inter process call
    ///
    /// - returns: A reference to the prepared instance variable
    func prepareXPC() -> NSXPCConnection? {
        
        // Check that the connection is valid before trying to do an inter process call to helper
        if(connection==nil) {
            connection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: NSXPCConnection.Options.privileged)
            connection?.remoteObjectInterface = NSXPCInterface(with: RemoteProcessProtocol.self)
            connection?.invalidationHandler = {
                self.connection?.invalidationHandler = nil
                OperationQueue.main.addOperation() {
                    self.connection = nil
                    NSLog("AppviewController: XPC Connection Invalidated")
                }
            }
            connection?.resume()
        }
        
        return connection
    }
    
    /// Install new helper daemon
    func installHelperDaemon() {
        
        NSLog("AppviewController: Privileged Helper daemon was not found, installing a new one...")

        // Create authorization reference for the user
        var authRef: AuthorizationRef?
        var authStatus = AuthorizationCreate(nil, nil, [], &authRef)
        
        // Check if the reference is valid
        guard authStatus == errAuthorizationSuccess else {
            NSLog("AppviewController: Authorization failed: \(authStatus)")
            return
        }
        
        // Ask user for the admin privileges to install the
        var authItem = AuthorizationItem(name: kSMRightBlessPrivilegedHelper, valueLength: 0, value: nil, flags: 0)
        var authRights = AuthorizationRights(count: 1, items: &authItem)
        let flags: AuthorizationFlags = [[], .interactionAllowed, .extendRights, .preAuthorize]
        authStatus = AuthorizationCreate(&authRights, nil, flags, &authRef)
        
        // Check if the authorization went succesfully
        guard authStatus == errAuthorizationSuccess else {
            NSLog("AppviewController: Couldn't obtain admin privileges: \(authStatus)")
            return
        }
        
        // Launch the privileged helper using SMJobBless tool
        var error: Unmanaged<CFError>? = nil
        
        if(SMJobBless(kSMDomainSystemLaunchd, HelperConstants.machServiceName as CFString, authRef, &error) == false) {
            let blessError = error!.takeRetainedValue() as Error
            NSLog("AppviewController: Bless Error: \(blessError)")
        } else {
            NSLog("AppviewController: \(HelperConstants.machServiceName) installed successfully")
        }
        
        // Release the Authorization Reference
        AuthorizationFree(authRef!, [])
    }
    
    /// Check if Helper daemon exists
    func checkIfHelperDaemonExists() -> Bool {
        
        let fileManager = FileManager.default
        
        if (!fileManager.fileExists(atPath: "/Library/PrivilegedHelperTools/com.suolapeikko.examples.PrivilegedTaskRunnerHelper")) {
            return false
        } else {
            return true
        }
    }

    /// Compare app's helper version to installed daemon's version and update if necessary
    func checkHelperVersionAndUpdateIfNecessary() {
       
        // Daemon path
        let helperURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/\(HelperConstants.machServiceName)")
        let helperBundleInfo = CFBundleCopyInfoDictionaryForURL(helperURL as CFURL)
        let helperInfo = helperBundleInfo! as NSDictionary
        let helperVersion = helperInfo["CFBundleVersion"] as! String
        
        NSLog("AppviewController: PrivilegedTaskRunner Bundle Version => \(helperVersion)")
        
        // When the connection is valid, do the actual inter process call
        let xpcService = prepareXPC()?.remoteObjectProxyWithErrorHandler() { error -> Void in
            NSLog("XPC error: \(error)")
            } as? RemoteProcessProtocol
        
        xpcService?.getVersion(reply: {
            installedVersion in
            NSLog("AppviewController: PrivilegedTaskRunner Helper Installed Version => \(installedVersion)")
            if(installedVersion != helperVersion) {
                self.installHelperDaemon()
            }
            else {
                NSLog("AppviewController: Bundle version matches privileged helper version, so no need to install")
            }
        })
    }
}
