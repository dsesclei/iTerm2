//
//  ProfilesColorsPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/14/14.
//
//

#import "iTermProfilePreferencesBaseViewController.h"

extern NSString *const iTermColorPreferencesDidDisappear;
extern NSString *const iTermColorPreferencesDidAppear;

@interface ProfilesColorsPreferencesViewController : iTermProfilePreferencesBaseViewController
+ (NSString *)nameOfPresetUsedByProfile:(Profile *)profile;
@end

@interface ProfilesColorsPreferencesViewController (Testing)
// The timer that will apply a color preset preview. Tests fire it instead of waiting.
@property (nonatomic, readonly) NSTimer *previewTimerForTesting;
// Replaces the light/dark mode selector, which normally comes from the nib.
- (void)setModeButtonForTesting:(NSPopUpButton *)modeButton;
@end
