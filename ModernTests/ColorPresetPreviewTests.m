// In Objective-C so the test can call private methods of
// ProfilesColorsPreferencesViewController and ProfileModel.

#import <XCTest/XCTest.h>

#import "ITAddressBookMgr.h"
#import "ProfilesColorsPreferencesViewController.h"
#import "iTermColorPresets.h"

@interface ProfileModel (ColorPresetPreviewTests)
- (instancetype)initWithName:(NSString *)name;
@end

@interface ProfilesColorsPreferencesViewController (ColorPresetPreviewTests) <NSMenuDelegate>
- (void)popupButtonWillPopUp:(id)sender;
- (void)loadColorPresetWithName:(NSString *)presetName prompt:(BOOL)prompt;
@end

@interface ColorPresetPreviewTests : XCTestCase <iTermProfilePreferencesBaseViewControllerDelegate>
@end

@implementation ColorPresetPreviewTests {
    ProfileModel *_model;
    NSString *_guid;
    // Keys passed to willSetObjectWithKey:.
    NSMutableArray<NSString *> *_announcedKeys;
}

- (void)testCancelingPreviewRestoresProfileWithOneReload {
    NSString *tabColorKey = KEY_TAB_COLOR COLORS_LIGHT_MODE_SUFFIX;
    NSString *matchColorKey = KEY_MATCH_COLOR COLORS_LIGHT_MODE_SUFFIX;
    // Not backed by user defaults.
    _model = [[ProfileModel alloc] initWithName:@"ColorPresetPreviewTests"];
    _guid = [ProfileModel freshGuid];
    // The profile sets a tab color, which the preset lacks and so removes. It sets no other
    // color, so the preset adds the rest.
    [_model addBookmark:@{ KEY_GUID: _guid,
                           KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE: @YES,
                           tabColorKey: [iTermColorPresets presetWithName:@"Tango Light"][KEY_FOREGROUND_COLOR] }];
    Profile *original = self.profilePreferencesCurrentProfile;
    _announcedKeys = [NSMutableArray array];

    // Without the nib, _mode is nil (selectedTag == 0, i.e. light mode).
    ProfilesColorsPreferencesViewController *controller =
        [[ProfilesColorsPreferencesViewController alloc] initWithNibName:nil bundle:nil];
    controller.delegate = self;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Color Presets"];

    [controller popupButtonWillPopUp:nil];
    // The same call the preview timer makes.
    [controller loadColorPresetWithName:@"Tango Light" prompt:NO];
    XCTAssertNil(self.profilePreferencesCurrentProfile[tabColorKey]);
    XCTAssertNotNil(self.profilePreferencesCurrentProfile[matchColorKey]);

    __block NSUInteger reloads = 0;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    id observer = [center addObserverForName:kReloadAllProfiles object:nil queue:nil usingBlock:^(NSNotification *note) {
        reloads++;
    }];
    [self addTeardownBlock:^{ [center removeObserver:observer]; }];

    // Moving off the preset restores the colors. Closing the menu then has nothing left to do.
    [controller menu:menu willHighlightItem:nil];
    [controller menuDidClose:menu];

    XCTAssertEqual(reloads, 1u);
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile, original);
    XCTAssertTrue([_announcedKeys containsObject:tabColorKey]);
    XCTAssertTrue([_announcedKeys containsObject:matchColorKey]);
}

#pragma mark - iTermProfilePreferencesBaseViewControllerDelegate

- (Profile *)profilePreferencesCurrentProfile { return [_model bookmarkWithGuid:_guid]; }
- (ProfileModel *)profilePreferencesCurrentModel { return _model; }
- (BOOL)editingTmuxSession { return NO; }
- (BOOL)profilePreferencesRevealViewController:(iTermProfilePreferencesBaseViewController *)vc { return NO; }
- (void)profilePreferencesViewController:(iTermProfilePreferencesBaseViewController *)vc willSetObjectWithKey:(NSString *)key {
    [_announcedKeys addObject:key];
}
- (void)profilePreferencesContentViewSizeDidChange:(iTermSizeRememberingView *)view {}
- (void)profilePreferencesSessionTypeDidChange {}

@end
