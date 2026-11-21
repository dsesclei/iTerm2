#import <XCTest/XCTest.h>

#import "ITAddressBookMgr.h"
#import "ProfilesColorsPreferencesViewController.h"
#import "iTermColorPresets.h"

@interface ProfileModel (ColorPresetPreviewTests)
- (instancetype)initWithName:(NSString *)name;
@end

@interface ProfilesColorsPreferencesViewController (ColorPresetPreviewTests) <NSMenuDelegate>
- (void)loadColorPreset:(NSMenuItem *)item;
@end

@interface ColorPresetPreviewTests : XCTestCase <iTermProfilePreferencesBaseViewControllerDelegate>
@end

@implementation ColorPresetPreviewTests {
    ProfileModel *_model;
    NSString *_guid;
    ProfilesColorsPreferencesViewController *_controller;
    NSMenu *_menu;
}

- (void)setUp {
    [super setUp];
    // A model created this way has no backing user defaults.
    _model = [[ProfileModel alloc] initWithName:@"ColorPresetPreviewTests"];
    _guid = [ProfileModel freshGuid];
    [_model addBookmark:@{ KEY_GUID: _guid }];
    _controller = [[ProfilesColorsPreferencesViewController alloc] initWithNibName:nil bundle:nil];
    _controller.delegate = self;
    _menu = [[NSMenu alloc] initWithTitle:@"Color Presets"];
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

- (void)hoverPreset:(NSString *)name {
    [_controller menu:_menu willHighlightItem:[self itemForPreset:name]];
    NSTimer *timer = [_controller valueForKey:@"timer"];
    XCTAssertNotNil(timer);
    [timer fire];
}

- (void)testRemovingHighlightRestoresOriginalColorsWithOneReload {
    Profile *original = self.profilePreferencesCurrentProfile;
    [self hoverPreset:@"Tango Light"];
    [self hoverPreset:@"Tango Dark"];
    XCTAssertNotEqualObjects(self.profilePreferencesCurrentProfile[KEY_BACKGROUND_COLOR], original[KEY_BACKGROUND_COLOR]);

    __block NSUInteger reloads = 0;
    NSThread *thread = NSThread.currentThread;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    id observer = [center addObserverForName:kReloadAllProfiles object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (NSThread.currentThread == thread) {
            reloads++;
        }
    }];
    [self addTeardownBlock:^{ [center removeObserver:observer]; }];
    [_controller menu:_menu willHighlightItem:nil];
    XCTAssertEqual(reloads, 1u);
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile, original);

    // Closing before the next preview fires should do no more work.
    [_controller menu:_menu willHighlightItem:[self itemForPreset:@"Tango Light"]];
    NSTimer *pending = [_controller valueForKey:@"timer"];
    XCTAssertTrue(pending.isValid);
    [_controller menuDidClose:_menu];
    XCTAssertFalse(pending.isValid);
    XCTAssertEqual(reloads, 1u);
}

- (void)testCancelingDarkPreviewRestoresRemovedTabColorAndKeepsLightModeEdit {
    NSPopUpButton *mode = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [mode addItemWithTitle:@"Dark"];
    mode.selectedItem.tag = 1;
    [_controller setValue:mode forKey:@"mode"];
    NSDictionary *color = [iTermColorPresets presetWithName:@"Tango Dark"][KEY_FOREGROUND_COLOR];
    [_model setObjectsFromDictionary:@{ KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE: @YES,
                                        KEY_TAB_COLOR COLORS_DARK_MODE_SUFFIX: color }
                           inProfile:self.profilePreferencesCurrentProfile];
    MutableProfile *expected = [self.profilePreferencesCurrentProfile mutableCopy];
    [self hoverPreset:@"Tango Light"];
    XCTAssertNil(self.profilePreferencesCurrentProfile[KEY_TAB_COLOR COLORS_DARK_MODE_SUFFIX]);

    NSString *lightKey = KEY_BACKGROUND_COLOR COLORS_LIGHT_MODE_SUFFIX;
    [_model setObject:color forKey:lightKey inBookmark:self.profilePreferencesCurrentProfile];
    expected[lightKey] = color;
    [_controller menuDidClose:_menu];
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile, expected);
}

- (void)testChoosingDualModePresetAfterPreviewRestoresSharedColors {
    Profile *original = self.profilePreferencesCurrentProfile;
    [self hoverPreset:@"Tango Light"];
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
    [self hoverPreset:@"Tango Dark"];
    _guid = [ProfileModel freshGuid];
    [_model addBookmark:@{ KEY_GUID: _guid, KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE: @YES }];
    Profile *second = self.profilePreferencesCurrentProfile;
    [self hoverPreset:@"Tango Light"];
    XCTAssertEqualObjects([_model bookmarkWithGuid:firstGuid], first);
    XCTAssertNotEqualObjects(self.profilePreferencesCurrentProfile, second);
    [_controller menuDidClose:_menu];
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile, second);
}

- (Profile *)profilePreferencesCurrentProfile { return [_model bookmarkWithGuid:_guid]; }
- (ProfileModel *)profilePreferencesCurrentModel { return _model; }
- (BOOL)editingTmuxSession { return NO; }
- (BOOL)profilePreferencesRevealViewController:(iTermProfilePreferencesBaseViewController *)vc { return NO; }
- (void)profilePreferencesViewController:(iTermProfilePreferencesBaseViewController *)vc willSetObjectWithKey:(NSString *)key {}
- (void)profilePreferencesContentViewSizeDidChange:(iTermSizeRememberingView *)view {}
- (void)profilePreferencesSessionTypeDidChange {}

@end
