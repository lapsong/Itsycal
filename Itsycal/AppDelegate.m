//
//  AppDelegate.m
//  Itsycal
//
//  Created by Sanjay Madan on 2/4/15.
//  Copyright (c) 2015 mowglii.com. All rights reserved.
//

#import "AppDelegate.h"
#import "Itsycal.h"
#import "ItsycalWindow.h"
#import "ViewController.h"
#import "MASShortcut/MASShortcutBinder.h"
#import "MASShortcut/MASShortcutMonitor.h"

@implementation AppDelegate
{
    NSWindowController  *_wc;
    ViewController      *_vc;
}

+ (void)initialize
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults registerDefaults:@{
        kPinItsycal:       @(NO),
        kShowWeeks:        @(NO),
        kHighlightWeekend: @(NO),
        kShowEventDays:    @7,
        kWeekStartDOW:     @0, // Sun=0, Mon=1,... (MoCalendar.h)
        kShowMonthInIcon:  @(NO),
        kShowDayOfWeekInIcon: @(NO)
    }];
    
    // Constrain kShowEventDays to values 0...7 in (unlikely) case it is invalid.
    NSInteger validDays = MIN(MAX([defaults integerForKey:kShowEventDays], 0), 7);
    [defaults setInteger:validDays forKey:kShowEventDays];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // On macOS 10.12+, ensure the user has moved Itsycal to the
    // /Applications folder. Having the user manually move Itsycal
    // to /Applications turns off Gatekeeper Path Randomization
    // and allows Itsycal to be updated with Sparkle. :P
    if (OSVersionIsAtLeast(10, 12, 0)) {
        [self checkIfRunFromApplicationsFolder];
    }
    
    // Register keyboard shortcut.
    [[MASShortcutBinder sharedBinder] bindShortcutWithDefaultsKey:kKeyboardShortcut toAction:^{
         [_vc keyboardShortcutActivated];
     }];
    
    _vc = [ViewController new];
    _wc = [[NSWindowController alloc] initWithWindow:[ItsycalWindow  new]];
    _wc.contentViewController = _vc;
    _wc.window.delegate = _vc;
    
    // Don't bother trying to load the menu extra on 10.11+. All we
    // will do is clutter up the error log with failure messages.
    if (OSVersionIsAtLeast(10, 11, 0)) {
        return;
    }
    
    // Load the menu extra asynchronously so that if it fails
    // and re-tries, it won't hold up the rest of the app.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self loadMenuExtra];
    });
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    [self removeMenuExtra];
    [_vc removeStatusItem];
    [[MASShortcutMonitor sharedMonitor] unregisterAllShortcuts];
}

#pragma mark -
#pragma mark Applications folder check

- (void)checkIfRunFromApplicationsFolder
{
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSArray *applicationDirs = NSSearchPathForDirectoriesInDomains(NSApplicationDirectory, NSLocalDomainMask, YES);
    for (NSString *appDir in applicationDirs) {
        if ([bundlePath hasPrefix:appDir]) {
            return; // Ok, Itsycal is being run from /Applications.
        }
    }
    // Itsycal is not being run from /Applications.
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    NSAlert *alert = [NSAlert new];
    alert.messageText = NSLocalizedString(@"Move Itsycal to the Applications folder", nil);
    alert.informativeText = NSLocalizedString(@"Itsycal must be run from the Applications folder in order to work properly.\n\nPlease quit Itsycal, move it to the Applications folder, and relaunch.", nil);
    alert.icon = [NSImage imageNamed:@"move"];
    [alert addButtonWithTitle:NSLocalizedString(@"Quit Itsycal", @"")];
    [alert runModal];
    [NSApp terminate:nil];
}

#pragma mark -
#pragma mark MenuExtra

// Adapted from MenuMeters source.
// www.ragingmenace.com/software/menumeters/

// Routines to handle adding and remove menu extras in HIServices (from ASM source)
int CoreMenuExtraGetMenuExtra(CFStringRef identifier, void *menuExtra);
int CoreMenuExtraAddMenuExtra(CFURLRef path, int position, int whoCares, int whoCares2, int whoCares3, int whoCares4);
int CoreMenuExtraRemoveMenuExtra(void *menuExtra, int whoCares);

// How long to wait for Extras to add once CoreMenuExtraAddMenuExtra returns.
static const int kWaitForExtraLoadMicroSec     = 10000000;
static const int kWaitForExtraLoadStepMicroSec = 250000;

- (void)loadMenuExtra
{
    if ([self isMenuExtraLoaded]) {
        NSLog(@"Menuextra is already loaded!");
        return;
    }
    
    NSURL *menuCrackerURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"MenuCracker" ofType:@"menu"]];
    NSURL *menuExtraURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"ItsycalExtra" ofType:@"menu"]];
    
    // Load the crack. With MenuCracker 2.x multiple loads are allowed, so
    // we don't care if someone else has the MenuCracker 2.x bundle loaded.
    // Plus, since MC 2.x does dodgy things with the load we can't actually
    // find out if its loaded.
    CoreMenuExtraAddMenuExtra((__bridge CFURLRef)menuCrackerURL, 0, 0, 0, 0, 0);
    
    // Load actual request
    CoreMenuExtraAddMenuExtra((__bridge CFURLRef)menuExtraURL, 0, 0, 0, 0, 0);
    
    // Wait for the item to load.
    int microSlept = 0;
    while (![self isMenuExtraLoaded] && (microSlept < kWaitForExtraLoadMicroSec)) {
        microSlept += kWaitForExtraLoadStepMicroSec;
        usleep(kWaitForExtraLoadStepMicroSec);
    }
    
    // Try again if needed.
    if (![self isMenuExtraLoaded]) {
        microSlept = 0;
        CoreMenuExtraAddMenuExtra((__bridge CFURLRef)menuExtraURL, 0, 0, 0, 0, 0);
        while (![self isMenuExtraLoaded] && (microSlept < kWaitForExtraLoadMicroSec)) {
            microSlept += kWaitForExtraLoadStepMicroSec;
            usleep(kWaitForExtraLoadStepMicroSec);
        }
    }
    
    // At this point, either the MenuExtra is loaded or it isn't.
    // If not, Itsycal will run as a normal NSStatusItem app.
}

- (BOOL)isMenuExtraLoaded
{
    void *anExtra = NULL;
    if (!CoreMenuExtraGetMenuExtra((__bridge CFStringRef)kItsycalExtraBundleID, &anExtra) && anExtra) {
        return YES;
    }
    return NO;
}

- (void)removeMenuExtra
{
    void *anExtra = NULL;
    if (!CoreMenuExtraGetMenuExtra((__bridge CFStringRef)kItsycalExtraBundleID, &anExtra) && anExtra) {
        CoreMenuExtraRemoveMenuExtra(anExtra, 0);
    }
}

@end
