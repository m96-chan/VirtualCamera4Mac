import Foundation
import CoreMediaIO

// Entry point for the Camera Extension. `startService` registers the provider
// with CoreMediaIO; the run loop keeps the process alive to service clients.
let providerSource = ExtensionProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)

CFRunLoopRun()
