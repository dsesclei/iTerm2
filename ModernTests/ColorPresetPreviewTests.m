// These tests are in Objective-C because they call selectors that are private to
// ProfilesColorsPreferencesViewController.m and ProfileModel.m, which Swift can't see.

#import <XCTest/XCTest.h>

#import "ITAddressBookMgr.h"
#import "NSObject+iTerm.h"
#import "ProfilesColorsPreferencesViewController.h"
#import "iTermColorPresets.h"
#import "iTermProfilePreferences.h"

@interface ProfileModel (ColorPresetPreviewTests)
- (instancetype)initWithName:(NSString *)name;
@end

// The pop-up notification handler, the method a preview's timer calls, and the menu delegate
// methods aren't in the public header.
@interface ProfilesColorsPreferencesViewController (ColorPresetPreviewTests) <NSMenuDelegate>
- (void)popupButtonWillPopUp:(id)sender;
- (void)loadColorPresetWithName:(NSString *)presetName prompt:(BOOL)prompt;
@end

@interface ColorPresetPreviewTests : XCTestCase <iTermProfilePreferencesBaseViewControllerDelegate>
@end

@implementation ColorPresetPreviewTests {
    ProfileModel *_model;
    NSString *_guid;
    ProfilesColorsPreferencesViewController *_controller;
    NSMenu *_menu;
    // Keys the controller announced through -profilePreferencesViewController:willSetObjectWithKey:.
    NSMutableArray<NSString *> *_announcedKeys;
}

- (void)setUp {
    [super setUp];
    // A model created this way has no backing user defaults.
    _model = [[ProfileModel alloc] initWithName:@"ColorPresetPreviewTests"];
    _guid = [ProfileModel freshGuid];
    [_model addBookmark:@{ KEY_GUID: _guid }];
    [self loadPreset:@"Solarized Dark" into:0];
    // The nib isn't loaded, so there is no mode selector. The controller treats that as light mode.
    _controller = [[ProfilesColorsPreferencesViewController alloc] initWithNibName:nil bundle:nil];
    _controller.delegate = self;
    _menu = [[NSMenu alloc] initWithTitle:@"Color Presets"];
    _announcedKeys = [NSMutableArray array];
}

// Loads a preset into the selected profile the way choosing it does. `destination` is 0 for the
// shared colors, or the light or dark mode ones. Tests compare whole profiles, so they start with
// the preset's colors in place.
- (void)loadPreset:(NSString *)name into:(iTermColorPresetMode)destination {
    XCTAssertTrue([_model addColorPresetNamed:name
                                    toProfile:self.profilePreferencesCurrentProfile
                                         from:0
                                           to:destination]);
}

// Gives the profile separate light and dark mode colors, with the light ones filled in.
- (void)useSeparateColors {
    [self loadPreset:@"Solarized Dark" into:iTermColorPresetModeLight];
    [_model setObject:@YES
               forKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE
           inBookmark:self.profilePreferencesCurrentProfile];
}

// Does what the preview timer does when the highlight has stayed on a preset.
- (void)previewPreset:(NSString *)name {
    [_controller loadColorPresetWithName:name prompt:NO];
}

// Counts kReloadAllProfiles notifications posted on this thread until the test ends.
- (NSUInteger (^)(void))reloadCounter {
    __block NSUInteger reloads = 0;
    NSThread *thread = NSThread.currentThread;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    id observer = [center addObserverForName:kReloadAllProfiles object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (NSThread.currentThread == thread) {
            reloads++;
        }
    }];
    [self addTeardownBlock:^{ [center removeObserver:observer]; }];
    return ^NSUInteger { return reloads; };
}

- (NSArray<NSString *> *)keysThatDifferBetween:(Profile *)a and:(Profile *)b {
    NSMutableSet<NSString *> *keys = [NSMutableSet setWithArray:a.allKeys];
    [keys addObjectsFromArray:b.allKeys];
    return [keys.allObjects filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *key, NSDictionary *bindings) {
        return ![NSObject object:a[key] isEqualToObject:b[key]];
    }]];
}

- (void)testRemovingHighlightRestoresColorsWithOneReload {
    Profile *original = self.profilePreferencesCurrentProfile;
    [_controller popupButtonWillPopUp:nil];
    [self previewPreset:@"Tango Light"];
    [self previewPreset:@"Tango Dark"];
    NSArray<NSString *> *changedKeys = [self keysThatDifferBetween:original
                                                               and:self.profilePreferencesCurrentProfile];
    // One reload for a single key would prove nothing.
    XCTAssertGreaterThan(changedKeys.count, 1u);

    NSUInteger (^reloads)(void) = [self reloadCounter];
    [_announcedKeys removeAllObjects];
    [_controller menu:_menu willHighlightItem:nil];
    XCTAssertEqual(reloads(), 1u);
    // Each restored key is announced to the delegate once, and nothing else is.
    XCTAssertEqualObjects([NSCountedSet setWithArray:_announcedKeys], [NSCountedSet setWithArray:changedKeys]);
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile, original);

    // Nothing is left to restore when the menu closes.
    [_controller menuDidClose:_menu];
    XCTAssertEqual(reloads(), 1u);
}

- (void)testCancelingPreviewRestoresTabColorRemovedByPreset {
    [self useSeparateColors];
    NSString *tabColorKey = KEY_TAB_COLOR COLORS_LIGHT_MODE_SUFFIX;
    [_model setObject:[iTermColorPresets presetWithName:@"Tango Dark"][KEY_FOREGROUND_COLOR]
               forKey:tabColorKey
           inBookmark:self.profilePreferencesCurrentProfile];
    Profile *original = self.profilePreferencesCurrentProfile;

    [_controller popupButtonWillPopUp:nil];
    [self previewPreset:@"Tango Light"];
    XCTAssertNil(self.profilePreferencesCurrentProfile[tabColorKey]);
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile[KEY_BACKGROUND_COLOR COLORS_LIGHT_MODE_SUFFIX],
                          [iTermColorPresets presetWithName:@"Tango Light"][KEY_BACKGROUND_COLOR]);
    [_controller menuDidClose:_menu];
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile, original);
}

// No built-in preset has a tab color, so this takes a custom one.
- (void)testCancelingPreviewRemovesTabColorAddedByPreset {
    [self useSeparateColors];
    NSString *tabColorKey = KEY_TAB_COLOR COLORS_LIGHT_MODE_SUFFIX;
    Profile *original = self.profilePreferencesCurrentProfile;
    XCTAssertNil(original[tabColorKey]);

    NSMutableDictionary *preset = [[iTermColorPresets presetWithName:@"Tango Dark"] mutableCopy];
    preset[KEY_TAB_COLOR] = preset[KEY_ANSI_1_COLOR];
    NSString *name = NSUUID.UUID.UUIDString;
    [iTermColorPresets addColorPreset:name withColors:preset];
    [self addTeardownBlock:^{ [iTermColorPresets deletePresetWithName:name]; }];

    [_controller popupButtonWillPopUp:nil];
    [self previewPreset:name];
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile[tabColorKey], preset[KEY_TAB_COLOR]);
    [_controller menuDidClose:_menu];
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile, original);
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
