// These tests are in Objective-C because they call selectors that are private to
// ProfilesColorsPreferencesViewController.m, ProfileModel.m, and iTermDynamicProfileManager.m,
// which Swift can't see.

#import <XCTest/XCTest.h>

#import "ITAddressBookMgr.h"
#import "NSObject+iTerm.h"
#import "ProfilesColorsPreferencesViewController.h"
#import "iTermColorPresets.h"
#import "iTermDynamicProfileManager.h"
#import "iTermProfilePreferences.h"

@interface ProfileModel (ColorPresetPreviewTests)
- (instancetype)initWithName:(NSString *)name;
@end

@interface iTermDynamicProfileManager (ColorPresetPreviewTests)
- (void)addDynamicProfile:(Profile *)profile;
@end

// The menu delegate methods, the preset menu items' action, and the pop-up notification handler
// aren't in the public header.
@interface ProfilesColorsPreferencesViewController (ColorPresetPreviewTests) <NSMenuDelegate>
- (void)loadColorPreset:(NSMenuItem *)item;
- (void)popupButtonWillPopUp:(id)sender;
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
    _controller = [[ProfilesColorsPreferencesViewController alloc] initWithNibName:nil bundle:nil];
    _controller.delegate = self;
    _menu = [[NSMenu alloc] initWithTitle:@"Color Presets"];
    _announcedKeys = [NSMutableArray array];
}

- (NSMenuItem *)itemForPreset:(NSString *)name {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:name action:@selector(loadColorPreset:) keyEquivalent:@""];
    item.identifier = name;
    return item;
}

- (void)tearDown {
    [_controller menuDidClose:_menu];
    [super tearDown];
}

// Loads a preset into the selected profile the way choosing it does. `destination` is 0 for the
// shared colors, or the light or dark mode ones. Canceling a preview puts back each color's
// value, and a color the profile didn't have is written as its default. Tests compare whole
// profiles, so they start with every color in place.
- (void)loadPreset:(NSString *)name into:(iTermColorPresetMode)destination {
    XCTAssertTrue([_model addColorPresetNamed:name
                                    toProfile:self.profilePreferencesCurrentProfile
                                         from:0
                                           to:destination]);
}

- (void)hoverPreset:(NSString *)name {
    [_controller menu:_menu willHighlightItem:[self itemForPreset:name]];
    NSTimer *timer = _controller.previewTimerForTesting;
    XCTAssertNotNil(timer);
    [timer fire];
}

- (void)selectDarkMode {
    NSPopUpButton *mode = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [mode addItemWithTitle:@"Dark"];
    mode.selectedItem.tag = 1;
    [_controller setModeButtonForTesting:mode];
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

- (void)testRemovingHighlightRestoresOriginalColorsWithOneReload {
    Profile *original = self.profilePreferencesCurrentProfile;
    [_controller popupButtonWillPopUp:nil];
    [self hoverPreset:@"Tango Light"];
    [self hoverPreset:@"Tango Dark"];
    Profile *previewed = self.profilePreferencesCurrentProfile;
    XCTAssertNotEqualObjects(previewed[KEY_BACKGROUND_COLOR], original[KEY_BACKGROUND_COLOR]);
    NSArray<NSString *> *changedKeys = [self keysThatDifferBetween:original and:previewed];
    // One reload for a single key would prove nothing.
    XCTAssertGreaterThan(changedKeys.count, 1u);

    NSUInteger (^reloads)(void) = [self reloadCounter];
    [_announcedKeys removeAllObjects];
    [_controller menu:_menu willHighlightItem:nil];
    XCTAssertEqual(reloads(), 1u);
    // Each restored key is announced to the delegate once, and nothing else is.
    XCTAssertEqualObjects([NSCountedSet setWithArray:_announcedKeys], [NSCountedSet setWithArray:changedKeys]);
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile, original);

    // Closing before the next preview fires should do no more work.
    [_announcedKeys removeAllObjects];
    [_controller menu:_menu willHighlightItem:[self itemForPreset:@"Tango Light"]];
    NSTimer *pending = _controller.previewTimerForTesting;
    XCTAssertTrue(pending.isValid);
    [_controller menuDidClose:_menu];
    XCTAssertFalse(pending.isValid);
    XCTAssertEqual(reloads(), 1u);
    XCTAssertEqualObjects(_announcedKeys, @[]);
}

- (void)testCancelingDarkPreviewRestoresRemovedTabColorAndKeepsLightModeEdit {
    [self selectDarkMode];
    NSDictionary *color = [iTermColorPresets presetWithName:@"Tango Dark"][KEY_FOREGROUND_COLOR];
    [self loadPreset:@"Solarized Dark" into:iTermColorPresetModeDark];
    [_model setObjectsFromDictionary:@{ KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE: @YES,
                                        KEY_TAB_COLOR COLORS_DARK_MODE_SUFFIX: color }
                           inProfile:self.profilePreferencesCurrentProfile];
    MutableProfile *expected = [self.profilePreferencesCurrentProfile mutableCopy];
    [_controller popupButtonWillPopUp:nil];
    [self hoverPreset:@"Tango Light"];
    XCTAssertNil(self.profilePreferencesCurrentProfile[KEY_TAB_COLOR COLORS_DARK_MODE_SUFFIX]);
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile[KEY_BACKGROUND_COLOR COLORS_DARK_MODE_SUFFIX],
                          [iTermColorPresets presetWithName:@"Tango Light"][KEY_BACKGROUND_COLOR]);

    NSString *lightKey = KEY_BACKGROUND_COLOR COLORS_LIGHT_MODE_SUFFIX;
    [_model setObject:color forKey:lightKey inBookmark:self.profilePreferencesCurrentProfile];
    expected[lightKey] = color;
    [_controller menuDidClose:_menu];
    // The dark colors are back, including the tab color the preview removed.
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile, expected);
}

// No built-in preset has a tab color, so this takes a custom one.
- (void)testCancelingPreviewRemovesTabColorAddedByPreset {
    [self selectDarkMode];
    [self loadPreset:@"Solarized Dark" into:iTermColorPresetModeDark];
    [_model setObject:@YES
               forKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE
           inBookmark:self.profilePreferencesCurrentProfile];
    Profile *original = self.profilePreferencesCurrentProfile;
    NSString *tabColorKey = KEY_TAB_COLOR COLORS_DARK_MODE_SUFFIX;
    XCTAssertNil(original[tabColorKey]);

    NSMutableDictionary *preset = [[iTermColorPresets presetWithName:@"Tango Dark"] mutableCopy];
    preset[KEY_TAB_COLOR] = preset[KEY_ANSI_1_COLOR];
    NSString *name = NSUUID.UUID.UUIDString;
    [iTermColorPresets addColorPreset:name withColors:preset];
    [self addTeardownBlock:^{ [iTermColorPresets deletePresetWithName:name]; }];

    [_controller popupButtonWillPopUp:nil];
    [self hoverPreset:name];
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile[tabColorKey], preset[KEY_TAB_COLOR]);
    [_controller menuDidClose:_menu];
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile, original);
}

// AppKit removes the highlight before it sends the action, which restores the colors first. This
// checks that choosing a preset doesn't depend on that order.
- (void)testChoosingDualModePresetDuringPreviewRestoresSharedColors {
    Profile *original = self.profilePreferencesCurrentProfile;
    [_controller popupButtonWillPopUp:nil];
    [self hoverPreset:@"Tango Light"];
    XCTAssertNotEqualObjects(self.profilePreferencesCurrentProfile[KEY_BACKGROUND_COLOR], original[KEY_BACKGROUND_COLOR]);
    [_controller loadColorPreset:[self itemForPreset:@"Solarized"]];
    [_controller menuDidClose:_menu];

    Profile *result = self.profilePreferencesCurrentProfile;
    NSDictionary *preset = [iTermColorPresets presetWithName:@"Solarized"];
    XCTAssertEqualObjects(result[KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE], @YES);
    XCTAssertEqualObjects(result[KEY_BACKGROUND_COLOR], original[KEY_BACKGROUND_COLOR]);
    XCTAssertEqualObjects(result[KEY_BACKGROUND_COLOR COLORS_LIGHT_MODE_SUFFIX], preset[KEY_BACKGROUND_COLOR COLORS_LIGHT_MODE_SUFFIX]);
    XCTAssertEqualObjects(result[KEY_BACKGROUND_COLOR COLORS_DARK_MODE_SUFFIX], preset[KEY_BACKGROUND_COLOR COLORS_DARK_MODE_SUFFIX]);
}

- (void)testChangingProfilesDuringTrackingRestoresEachProfile {
    NSString *firstGuid = _guid;
    Profile *first = self.profilePreferencesCurrentProfile;
    [_controller popupButtonWillPopUp:nil];
    [self hoverPreset:@"Tango Dark"];
    XCTAssertNotEqualObjects(self.profilePreferencesCurrentProfile, first);
    _guid = [ProfileModel freshGuid];
    [_model addBookmark:@{ KEY_GUID: _guid, KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE: @YES }];
    [self loadPreset:@"Solarized Dark" into:iTermColorPresetModeLight];
    Profile *second = self.profilePreferencesCurrentProfile;
    [_announcedKeys removeAllObjects];
    [self hoverPreset:@"Tango Light"];
    XCTAssertEqualObjects([_model bookmarkWithGuid:firstGuid], first);
    // The first profile is no longer selected, so restoring it doesn't go through the delegate.
    XCTAssertEqualObjects(_announcedKeys, @[]);
    XCTAssertNotEqualObjects(self.profilePreferencesCurrentProfile, second);
    [_controller menuDidClose:_menu];
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile, second);
    XCTAssertGreaterThan(_announcedKeys.count, 0u);
}

- (void)testOpeningMenuAfterMissedCloseKeepsLaterEdit {
    [_controller popupButtonWillPopUp:nil];
    [self hoverPreset:@"Tango Dark"];

    // No -menuDidClose:. A color is then changed while the preview's colors are still in place.
    NSDictionary *color = [iTermColorPresets presetWithName:@"Tango Light"][KEY_SELECTION_COLOR];
    XCTAssertNotNil(color);
    XCTAssertNotEqualObjects(self.profilePreferencesCurrentProfile[KEY_BACKGROUND_COLOR], color);
    [_model setObject:color forKey:KEY_BACKGROUND_COLOR inBookmark:self.profilePreferencesCurrentProfile];
    Profile *edited = self.profilePreferencesCurrentProfile;

    // Neither opening the menu again nor closing it goes back to the old snapshot.
    [_controller popupButtonWillPopUp:nil];
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile, edited);
    [_controller menuDidClose:_menu];
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile, edited);
}

// A rewritable dynamic profile writes its changes back to its file. Neither it nor its parent
// sets a background color here, so the file must not keep the one a canceled preview wrote.
- (void)testCancelingPreviewTakesPreviewedColorOutOfRewritableDynamicProfileFile {
    iTermDynamicProfileManager *manager = [iTermDynamicProfileManager sharedInstance];
    ProfileModel *model = [ProfileModel sharedInstance];
    NSString *parentGuid = [ProfileModel freshGuid];
    NSString *guid = [ProfileModel freshGuid];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[guid stringByAppendingPathExtension:@"json"]];
    [model addBookmark:@{ KEY_GUID: parentGuid, KEY_NAME: @"ColorPresetPreviewTests parent" }];
    NSDictionary *entry = @{ KEY_GUID: guid,
                             KEY_NAME: @"ColorPresetPreviewTests dynamic",
                             KEY_DYNAMIC_PROFILE_PARENT_GUID: parentGuid,
                             KEY_DYNAMIC_PROFILE_REWRITABLE: @YES,
                             KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE: @NO };
    NSData *data = [NSJSONSerialization dataWithJSONObject:[manager dictionaryForProfiles:@[ entry ]]
                                                   options:0
                                                     error:nil];
    XCTAssertTrue([data writeToFile:path atomically:YES]);
    [self addTeardownBlock:^{
        [model removeProfileWithGuid:guid];
        [model removeProfileWithGuid:parentGuid];
        [model flush];
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }];
    NSMutableArray<Profile *> *loaded = [NSMutableArray array];
    XCTAssertTrue([manager loadDynamicProfilesFromFile:path intoArray:loaded guids:[NSMutableSet set]]);
    XCTAssertEqual(loaded.count, 1u);
    [manager addDynamicProfile:loaded.firstObject];
    _model = model;
    _guid = guid;

    NSDictionary *(^backgroundInFile)(void) = ^NSDictionary *{
        NSArray<Profile *> *profiles = [manager profilesInFile:path fileType:nil];
        XCTAssertEqual(profiles.count, 1u);
        return profiles.firstObject[KEY_BACKGROUND_COLOR];
    };
    id original = [iTermProfilePreferences objectForKey:KEY_BACKGROUND_COLOR
                                              inProfile:self.profilePreferencesCurrentProfile];
    NSDictionary *previewed = [iTermColorPresets presetWithName:@"Tango Light"][KEY_BACKGROUND_COLOR];
    XCTAssertNotNil(original);
    XCTAssertNotEqualObjects(original, previewed);
    XCTAssertNil(backgroundInFile());

    [_controller popupButtonWillPopUp:nil];
    [self hoverPreset:@"Tango Light"];
    XCTAssertEqualObjects(backgroundInFile(), previewed);
    [_controller menuDidClose:_menu];
    XCTAssertEqualObjects([iTermProfilePreferences objectForKey:KEY_BACKGROUND_COLOR
                                                      inProfile:self.profilePreferencesCurrentProfile],
                          original);
    XCTAssertNil(backgroundInFile());
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
