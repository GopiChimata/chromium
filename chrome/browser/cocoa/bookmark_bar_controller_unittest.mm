// Copyright (c) 2009 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <Cocoa/Cocoa.h>

#include "base/basictypes.h"
#include "base/scoped_nsobject.h"
#import "chrome/browser/cocoa/bookmark_bar_controller.h"
#include "chrome/browser/cocoa/browser_test_helper.h"
#import "chrome/browser/cocoa/cocoa_test_helper.h"
#include "testing/gtest/include/gtest/gtest.h"

// Pretend BookmarkURLOpener delegate to keep track of requests
@interface BookmarkURLOpenerPong : NSObject<BookmarkURLOpener> {
 @public
  std::vector<GURL> urls_;
  std::vector<WindowOpenDisposition> dispositions_;
}
@end

@implementation BookmarkURLOpenerPong
- (void)openBookmarkURL:(const GURL&)url
            disposition:(WindowOpenDisposition)disposition {
  urls_.push_back(url);
  dispositions_.push_back(disposition);
}
- (void)clear {
  urls_.clear();
  dispositions_.clear();
}
@end


// NSCell that is pre-provided with a desired size that becomes the
// return value for -(NSSize)cellSize:.
@interface CellWithDesiredSize : NSCell {
 @private
  NSSize cellSize_;
}
@property(readonly) NSSize cellSize;
@end

@implementation CellWithDesiredSize

@synthesize cellSize = cellSize_;

- (id)initTextCell:(NSString*)string desiredSize:(NSSize)size {
  if ((self = [super initTextCell:string])) {
    cellSize_ = size;
  }
  return self;
}

@end

// Remember the number of times we've gotten a frameDidChange notification.
@interface BookmarkBarControllerTogglePong : BookmarkBarController {
@private
  int toggles_;
}
@property (readonly) int toggles;
@end

@implementation BookmarkBarControllerTogglePong

@synthesize toggles = toggles_;

- (void)frameDidChange {
  toggles_++;
}

@end


namespace {

static const int kContentAreaHeight = 500;
static const int kInfoBarViewHeight = 30;

class BookmarkBarControllerTest : public testing::Test {
 public:
  BookmarkBarControllerTest() {
    NSRect content_frame = NSMakeRect(0, 0, 800, kContentAreaHeight);
    // |infobar_frame| is set to be directly above |content_frame|.
    NSRect infobar_frame = NSMakeRect(0, kContentAreaHeight,
                                      800, kInfoBarViewHeight);
    NSRect parent_frame = NSMakeRect(0, 0, 800, 50);
    content_area_.reset([[NSView alloc] initWithFrame:content_frame]);
    infobar_view_.reset([[NSView alloc] initWithFrame:infobar_frame]);
    parent_view_.reset([[NSView alloc] initWithFrame:parent_frame]);
    [parent_view_ setHidden:YES];
    bar_.reset(
        [[BookmarkBarController alloc] initWithProfile:helper_.profile()
                                            parentView:parent_view_.get()
                                        webContentView:content_area_.get()
                                          infoBarsView:infobar_view_.get()
                                              delegate:nil]);

    InstallAndToggleBar(bar_.get());

    // Create a menu/item to act like a sender
    menu_.reset([[NSMenu alloc] initWithTitle:@"I_dont_care"]);
    menu_item_.reset([[NSMenuItem alloc]
                       initWithTitle:@"still_dont_care"
                              action:NULL
                       keyEquivalent:@""]);
    cell_.reset([[NSButtonCell alloc] init]);
    [menu_item_ setMenu:menu_.get()];
    [menu_ setDelegate:cell_.get()];
  }

  void InstallAndToggleBar(BookmarkBarController* bar) {
    // Force loading of the nib.
    [bar view];
    // Awkwardness to look like we've been installed.
    [parent_view_ addSubview:[bar view]];
    NSRect frame = [[[bar view] superview] frame];
    frame.origin.y = 100;
    [[[bar view] superview] setFrame:frame];

    // make sure it's open so certain things aren't no-ops
    [bar toggleBookmarkBar];
  }


  // Return a menu item that points to the right URL.
  NSMenuItem* ItemForBookmarkBarMenu(GURL& gurl) {
    node_.reset(new BookmarkNode(gurl));
    [cell_ setRepresentedObject:[NSValue valueWithPointer:node_.get()]];
    return menu_item_;
  }

  // Does NOT take ownership of node.
  NSMenuItem* ItemForBookmarkBarMenu(const BookmarkNode* node) {
    [cell_ setRepresentedObject:[NSValue valueWithPointer:node]];
    return menu_item_;
  }


  CocoaTestHelper cocoa_helper_;  // Inits Cocoa, creates window, etc...
  scoped_nsobject<NSView> content_area_;
  scoped_nsobject<NSView> infobar_view_;
  scoped_nsobject<NSView> parent_view_;
  BrowserTestHelper helper_;
  scoped_nsobject<BookmarkBarController> bar_;
  scoped_nsobject<NSMenu> menu_;
  scoped_nsobject<NSMenuItem> menu_item_;
  scoped_nsobject<NSButtonCell> cell_;
  scoped_ptr<BookmarkNode> node_;
};

TEST_F(BookmarkBarControllerTest, ShowHide) {
  // The test class opens the bar by default since many actions are
  // no-ops with it closed.  Set back to closed as a baseline.
  if ([bar_ isBookmarkBarVisible])
    [bar_ toggleBookmarkBar];

  // Start hidden.
  EXPECT_FALSE([bar_ isBookmarkBarVisible]);
  EXPECT_TRUE([[bar_ view] isHidden]);

  // Show and hide it by toggling.
  [bar_ toggleBookmarkBar];
  EXPECT_TRUE([bar_ isBookmarkBarVisible]);
  EXPECT_FALSE([[bar_ view] isHidden]);
  NSRect content_frame = [content_area_ frame];
  NSRect infobar_frame = [infobar_view_ frame];
  EXPECT_NE(content_frame.size.height, kContentAreaHeight);
  EXPECT_EQ(NSMaxY(content_frame), NSMinY(infobar_frame));
  EXPECT_EQ(kInfoBarViewHeight, infobar_frame.size.height);
  EXPECT_GT([[bar_ view] frame].size.height, 0);

  [bar_ toggleBookmarkBar];
  EXPECT_FALSE([bar_ isBookmarkBarVisible]);
  EXPECT_TRUE([[bar_ view] isHidden]);
  content_frame = [content_area_ frame];
  infobar_frame = [infobar_view_ frame];
  EXPECT_EQ(content_frame.size.height, kContentAreaHeight);
  EXPECT_EQ(NSMaxY(content_frame), NSMinY(infobar_frame));
  EXPECT_EQ(kInfoBarViewHeight, infobar_frame.size.height);
  EXPECT_EQ([[bar_ view] frame].size.height, 0);
}

// Make sure we're watching for frame change notifications.
TEST_F(BookmarkBarControllerTest, FrameChangeNotification) {
  scoped_nsobject<BookmarkBarControllerTogglePong> bar;
  bar.reset(
    [[BookmarkBarControllerTogglePong alloc]
          initWithProfile:helper_.profile()
               parentView:parent_view_.get()
           webContentView:content_area_.get()
             infoBarsView:infobar_view_.get()
                 delegate:nil]);
  InstallAndToggleBar(bar.get());

  EXPECT_GT([bar toggles], 0);

  // Hard to force toggles -- simple whacking the frame is inadequate.
  // TODO(jrg): find a way to set frame, force a toggle, and verify it.
}

// Confirm off the side button only enabled when reasonable.
TEST_F(BookmarkBarControllerTest, OffTheSideButtonEnable) {
  BookmarkModel* model = helper_.profile()->GetBookmarkModel();

  [bar_ loaded:model];
  EXPECT_FALSE([bar_ offTheSideButtonIsEnabled]);

  for (int i = 0; i < 2; i++) {
    model->SetURLStarred(GURL("http://www.foo.com"), L"small", true);
    EXPECT_FALSE([bar_ offTheSideButtonIsEnabled]);
  }

  for (int i = 0; i < 20; i++) {
    const BookmarkNode* parent = model->GetBookmarkBarNode();
    model->AddURL(parent, parent->GetChildCount(),
                  L"super duper wide title",
                  GURL("http://superfriends.hall-of-justice.edu"));
  }
  EXPECT_TRUE([bar_ offTheSideButtonIsEnabled]);
}

TEST_F(BookmarkBarControllerTest, TagMap) {
  int64 ids[] = { 1, 3, 4, 40, 400, 4000, 800000000, 2, 123456789 };
  std::vector<int32> tags;

  // Generate some tags
  for (unsigned int i = 0; i < arraysize(ids); i++) {
    tags.push_back([bar_ menuTagFromNodeId:ids[i]]);
  }

  // Confirm reverse mapping.
  for (unsigned int i = 0; i < arraysize(ids); i++) {
    EXPECT_EQ(ids[i], [bar_ nodeIdFromMenuTag:tags[i]]);
  }

  // Confirm uniqueness.
  std::sort(tags.begin(), tags.end());
  for (unsigned int i=0; i<(tags.size()-1); i++) {
    EXPECT_NE(tags[i], tags[i+1]);
  }
}

TEST_F(BookmarkBarControllerTest, MenuForFolderNode) {
  BookmarkModel* model = helper_.profile()->GetBookmarkModel();

  // First make sure something (e.g. "(empty)" string) is always present.
  NSMenu* menu = [bar_ menuForFolderNode:model->GetBookmarkBarNode()];
  EXPECT_GT([menu numberOfItems], 0);

  // Test two bookmarks.
  GURL gurl("http://www.foo.com");
  model->SetURLStarred(gurl, L"small", true);
  model->SetURLStarred(GURL("http://www.cnn.com"), L"bigger title", true);
  menu = [bar_ menuForFolderNode:model->GetBookmarkBarNode()];
  EXPECT_EQ([menu numberOfItems], 2);
  NSMenuItem *item = [menu itemWithTitle:@"bigger title"];
  EXPECT_TRUE(item);
  item = [menu itemWithTitle:@"small"];
  EXPECT_TRUE(item);
  if (item) {
    int64 tag = [bar_ nodeIdFromMenuTag:[item tag]];
    const BookmarkNode* node = model->GetNodeByID(tag);
    EXPECT_TRUE(node);
    EXPECT_EQ(gurl, node->GetURL());
  }

  // Test with an actual folder as well
  const BookmarkNode* parent = model->GetBookmarkBarNode();
  const BookmarkNode* folder = model->AddGroup(parent,
                                               parent->GetChildCount(),
                                               L"group");
  model->AddURL(folder, folder->GetChildCount(),
                L"f1", GURL("http://framma-lamma.com"));
  model->AddURL(folder, folder->GetChildCount(),
                L"f2", GURL("http://framma-lamma-ding-dong.com"));
  menu = [bar_ menuForFolderNode:model->GetBookmarkBarNode()];
  EXPECT_EQ([menu numberOfItems], 3);

  item = [menu itemWithTitle:@"group"];
  EXPECT_TRUE(item);
  EXPECT_TRUE([item hasSubmenu]);
  NSMenu *submenu = [item submenu];
  EXPECT_TRUE(submenu);
  EXPECT_EQ(2, [submenu numberOfItems]);
  EXPECT_TRUE([submenu itemWithTitle:@"f1"]);
  EXPECT_TRUE([submenu itemWithTitle:@"f2"]);
}

// Confirm openBookmark: forwards the request to the controller's delegate
TEST_F(BookmarkBarControllerTest, OpenBookmark) {
  GURL gurl("http://walla.walla.ding.dong.com");
  scoped_ptr<BookmarkNode> node(new BookmarkNode(gurl));
  scoped_nsobject<BookmarkURLOpenerPong> pong([[BookmarkURLOpenerPong alloc]
                                                init]);
  [bar_ setDelegate:pong.get()];

  scoped_nsobject<NSButtonCell> cell([[NSButtonCell alloc] init]);
  scoped_nsobject<NSButton> button([[NSButton alloc] init]);
  [button setCell:cell.get()];
  [cell setRepresentedObject:[NSValue valueWithPointer:node.get()]];

  [bar_ openBookmark:button];
  EXPECT_EQ(pong.get()->urls_[0], node->GetURL());
  EXPECT_EQ(pong.get()->dispositions_[0], CURRENT_TAB);

  [bar_ setDelegate:nil];
}

// Confirm opening of bookmarks works from the menus (different
// dispositions than clicking on the button).
TEST_F(BookmarkBarControllerTest, OpenBookmarkFromMenus) {
  scoped_nsobject<BookmarkURLOpenerPong> pong([[BookmarkURLOpenerPong alloc]
                                                init]);
  [bar_ setDelegate:pong.get()];

  const char* urls[] = { "http://walla.walla.ding.dong.com",
                         "http://i_dont_know.com",
                         "http://cee.enn.enn.dot.com" };
  SEL selectors[] = { @selector(openBookmarkInNewForegroundTab:),
                      @selector(openBookmarkInNewWindow:),
                      @selector(openBookmarkInIncognitoWindow:) };
  WindowOpenDisposition dispositions[] = { NEW_FOREGROUND_TAB,
                                           NEW_WINDOW,
                                           OFF_THE_RECORD };
  for (unsigned int i = 0;
       i < sizeof(dispositions)/sizeof(dispositions[0]);
       i++) {
    GURL gurl(urls[i]);
    [bar_ performSelector:selectors[i]
               withObject:ItemForBookmarkBarMenu(gurl)];
    EXPECT_EQ(pong.get()->urls_[0], gurl);
    EXPECT_EQ(pong.get()->dispositions_[0], dispositions[i]);
    [pong clear];
  }
  [bar_ setDelegate:nil];
}

TEST_F(BookmarkBarControllerTest, TestAddRemoveAndClear) {
  BookmarkModel* model = helper_.profile()->GetBookmarkModel();
  NSView* buttonView = [bar_ buttonView];
  EXPECT_EQ(0U, [[bar_ buttons] count]);
  unsigned int initial_subview_count = [[buttonView subviews] count];

  // Make sure a redundant call doesn't choke
  [bar_ clearBookmarkBar];
  EXPECT_EQ(0U, [[bar_ buttons] count]);
  EXPECT_EQ(initial_subview_count, [[buttonView subviews] count]);

  GURL gurl1("http://superfriends.hall-of-justice.edu");
  std::wstring title1(L"Protectors of the Universe");
  model->SetURLStarred(gurl1, title1, true);
  EXPECT_EQ(1U, [[bar_ buttons] count]);
  EXPECT_EQ(1+initial_subview_count, [[buttonView subviews] count]);

  GURL gurl2("http://legion-of-doom.gov");
  std::wstring title2(L"Bad doodz");
  model->SetURLStarred(gurl2, title2, true);
  EXPECT_EQ(2U, [[bar_ buttons] count]);
  EXPECT_EQ(2+initial_subview_count, [[buttonView subviews] count]);

  for (int i = 0; i < 3; i++) {
    // is_starred=false --> remove the bookmark
    model->SetURLStarred(gurl2, title2, false);
    EXPECT_EQ(1U, [[bar_ buttons] count]);
    EXPECT_EQ(1+initial_subview_count, [[buttonView subviews] count]);

    // and bring it back
    model->SetURLStarred(gurl2, title2, true);
    EXPECT_EQ(2U, [[bar_ buttons] count]);
    EXPECT_EQ(2+initial_subview_count, [[buttonView subviews] count]);
  }

  [bar_ clearBookmarkBar];
  EXPECT_EQ(0U, [[bar_ buttons] count]);
  EXPECT_EQ(initial_subview_count, [[buttonView subviews] count]);

  // Explicit test of loaded: since this is a convenient spot
  [bar_ loaded:model];
  EXPECT_EQ(2U, [[bar_ buttons] count]);
  EXPECT_EQ(2+initial_subview_count, [[buttonView subviews] count]);
}

// Make sure that each button we add marches to the right and does not
// overlap with the previous one.
TEST_F(BookmarkBarControllerTest, TestButtonMarch) {
  scoped_nsobject<NSMutableArray> cells([[NSMutableArray alloc] init]);

  CGFloat widths[] = { 10, 10, 100, 10, 500, 500, 80000, 60000, 1, 345 };
  for (unsigned int i = 0; i < arraysize(widths); i++) {
    NSCell* cell = [[CellWithDesiredSize alloc]
                     initTextCell:@"foo"
                      desiredSize:NSMakeSize(widths[i], 30)];
    [cells addObject:cell];
    [cell release];
  }

  int x_offset = 0;
  CGFloat x_end = x_offset;  // end of the previous button
  for (unsigned int i = 0; i < arraysize(widths); i++) {
    NSRect r = [bar_ frameForBookmarkButtonFromCell:[cells objectAtIndex:i]
                                            xOffset:&x_offset];
    EXPECT_GE(r.origin.x, x_end);
    x_end = NSMaxX(r);
  }
}

TEST_F(BookmarkBarControllerTest, CheckForGrowth) {
  BookmarkModel* model = helper_.profile()->GetBookmarkModel();
  GURL gurl1("http://www.google.com");
  std::wstring title1(L"x");
  model->SetURLStarred(gurl1, title1, true);

  GURL gurl2("http://www.google.com/blah");
  std::wstring title2(L"y");
  model->SetURLStarred(gurl2, title2, true);

  EXPECT_EQ(2U, [[bar_ buttons] count]);
  CGFloat width_1 = [[[bar_ buttons] objectAtIndex:0] frame].size.width;
  CGFloat x_2 = [[[bar_ buttons] objectAtIndex:1] frame].origin.x;

  NSButton* first = [[bar_ buttons] objectAtIndex:0];
  [[first cell] setTitle:@"This is a really big title; watch out mom!"];
  [bar_ checkForBookmarkButtonGrowth:first];

  // Make sure the 1st button is now wider, the 2nd one is moved over,
  // and they don't overlap.
  NSRect frame_1 = [[[bar_ buttons] objectAtIndex:0] frame];
  NSRect frame_2 = [[[bar_ buttons] objectAtIndex:1] frame];
  EXPECT_GT(frame_1.size.width, width_1);
  EXPECT_GT(frame_2.origin.x, x_2);
  EXPECT_GE(frame_2.origin.x, frame_1.origin.x + frame_1.size.width);
}

TEST_F(BookmarkBarControllerTest, DeleteBookmark) {
  BookmarkModel* model = helper_.profile()->GetBookmarkModel();

  const char* urls[] = { "https://secret.url.com",
                         "http://super.duper.web.site.for.doodz.gov",
                         "http://www.foo-bar-baz.com/" };
  const BookmarkNode* parent = model->GetBookmarkBarNode();
  for (unsigned int i = 0; i < arraysize(urls); i++) {
    model->AddURL(parent, parent->GetChildCount(),
                  L"title", GURL(urls[i]));
  }
  EXPECT_EQ(3, parent->GetChildCount());
  const BookmarkNode* middle_node = parent->GetChild(1);

  NSMenuItem* item = ItemForBookmarkBarMenu(middle_node);
  [bar_ deleteBookmark:item];
  EXPECT_EQ(2, parent->GetChildCount());
  EXPECT_EQ(parent->GetChild(0)->GetURL(), GURL(urls[0]));
  // node 2 moved into spot 1
  EXPECT_EQ(parent->GetChild(1)->GetURL(), GURL(urls[2]));
}

TEST_F(BookmarkBarControllerTest, OpenAllBookmarks) {
  scoped_nsobject<BookmarkURLOpenerPong> pong([[BookmarkURLOpenerPong alloc]
                                                init]);
  [bar_ setDelegate:pong.get()];

  BookmarkModel* model = helper_.profile()->GetBookmarkModel();
  const BookmarkNode* parent = model->GetBookmarkBarNode();
  // { one, { two-one, two-two }, three }
  model->AddURL(parent, parent->GetChildCount(),
                L"title", GURL("http://one.com"));
  const BookmarkNode* folder = model->AddGroup(parent,
                                               parent->GetChildCount(),
                                               L"group");
  model->AddURL(folder, folder->GetChildCount(),
                L"title", GURL("http://two-one.com"));
  model->AddURL(folder, folder->GetChildCount(),
                L"title", GURL("http://two-two.com"));
  model->AddURL(parent, parent->GetChildCount(),
                L"title", GURL("https://three.com"));
  [bar_ openAllBookmarks:nil];

  EXPECT_EQ(pong.get()->urls_.size(), 4U);
  EXPECT_EQ(pong.get()->dispositions_.size(), 4U);

  // I can't use EXPECT_EQ() here since the macro can't expand
  // properly (no way to print the value of an iterator).
  std::vector<GURL>::iterator i;
  std::vector<GURL>::iterator begin = pong.get()->urls_.begin();
  std::vector<GURL>::iterator end = pong.get()->urls_.end();
  i = find(begin, end, GURL("http://two-one.com"));
  EXPECT_FALSE(i == end);
  i = find(begin, end, GURL("https://three.com"));
  EXPECT_FALSE(i == end);
  i = find(begin, end, GURL("https://will-not-be-found.com"));
  EXPECT_TRUE(i == end);

  EXPECT_EQ(pong.get()->dispositions_[3], NEW_BACKGROUND_TAB);

  [bar_ setDelegate:nil];
}

// TODO(jrg): write a test to confirm that nodeFavIconLoaded calls
// checkForBookmarkButtonGrowth:.

// TODO(jrg): Make sure showing the bookmark bar calls loaded: (to
// process bookmarks)
TEST_F(BookmarkBarControllerTest, ShowAndLoad) {
}

// TODO(jrg): Test cellForBookmarkNode:
TEST_F(BookmarkBarControllerTest, Cell) {
}

TEST_F(BookmarkBarControllerTest, Contents) {
  // TODO(jrg): addNodesToBar has a LOT of TODOs; when flushed out, write
  // appropriate tests.
}

// Test drawing, mostly to ensure nothing leaks or crashes.
TEST_F(BookmarkBarControllerTest, Display) {
  [[bar_ view] display];
}

// Cannot test these methods since they simply call a single static
// method, BookmarkEditor::Show(), which is impossible to mock.
// editBookmark:, addPage:


}  // namespace
