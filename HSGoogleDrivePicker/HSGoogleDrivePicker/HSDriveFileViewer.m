//
//  ViewController.m
//  gdrive
//
//  Created by Rob Jonson on 13/10/2015.
//  Copyright © 2015 HobbyistSoftware. All rights reserved.
//

#import "HSDriveFileViewer.h"
#import "HSDriveManager.h"
#import "AsyncImageView.h"
#import "GTMOAuth2ViewControllerTouch.h"
#import "UIScrollView+SVPullToRefresh.h"


@interface HSDriveFileViewer () <UITableViewDataSource,UITableViewDelegate>



@property (retain) UILabel *output;

@property (retain) HSDriveManager *manager;
@property (retain) UITableView *table;
@property (assign) UIToolbar *toolbar;
@property (retain) GTLDriveFileList *fileList;
@property (retain) UIImage *blankImage;
@property (retain) UIBarButtonItem *upItem;
@property (retain) NSMutableArray *folderTrail;
@property (assign) BOOL showShared;



@end


@implementation HSDriveFileViewer

static NSString *const kKeychainItemName = @"Drive API";

- (instancetype)initWithManager:(HSDriveManager *)manager
{
    self = [super init];
    if (self)
    {
        [self setTitle:@"Google Drive"];
        
        self.manager=manager;
        self.modalPresentationStyle=UIModalPresentationPageSheet;
        
        UIGraphicsBeginImageContext(CGSizeMake(40, 40));
        CGContextAddRect(UIGraphicsGetCurrentContext(), CGRectMake(0, 0, 40, 40)); // this may not be necessary
        self.blankImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        self.folderTrail=[NSMutableArray arrayWithObject:@"root"];
    }
    return self;
}

- (instancetype)initWithId:(NSString*)clientId secret:(NSString*)secret
{
    return [self initWithManager:[[HSDriveManager alloc] initWithId:clientId secret:secret]];
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationController.navigationBar.translucent = NO;
    [self.navigationController.navigationBar setTintColor:[UIColor colorWithRed:0.541 green:0.855 blue:0.302 alpha:1.0]];
    [self.navigationController.navigationBar setTitleTextAttributes:@{NSFontAttributeName: [UIFont fontWithName:@"HelveticaNeue" size:16.0], NSKernAttributeName: @2.0}];
    
    [self.view setBackgroundColor:[UIColor whiteColor]];
    
    // Create a UITextView to display output.
    UILabel *output=[[UILabel alloc] initWithFrame:CGRectMake(40, 100, self.view.bounds.size.width-80, 40)];
    output.numberOfLines=0;
    output.textAlignment=NSTextAlignmentCenter;
    output.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:output];
    self.output=output;
    
    UIToolbar *toolbar=[UIToolbar new];
    [toolbar setTranslatesAutoresizingMaskIntoConstraints:NO];
    [toolbar setTintColor:[UIColor colorWithRed:0.541 green:0.855 blue:0.302 alpha:1.0]];
    self.toolbar=toolbar;
    [self.view addSubview:toolbar];
    
    UITableView *tableView=[[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    [tableView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [tableView setDelegate:self];
    [tableView setDataSource:self];
    
    [tableView addPullToRefreshWithActionHandler:^{
        [self getFiles];
    }];
    
    [self.view addSubview:tableView];
    self.table=tableView;
    
    NSDictionary *views = NSDictionaryOfVariableBindings(toolbar,tableView);
    
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"|[toolbar]|"
                                                                      options:NSLayoutFormatDirectionLeftToRight
                                                                      metrics:nil
                                                                        views:views]];
    
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"|[tableView]|"
                                                                      options:NSLayoutFormatDirectionLeftToRight
                                                                      metrics:nil
                                                                        views:views]];
    
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[toolbar(44)][tableView]|"
                                                                      options:NSLayoutFormatDirectionLeftToRight
                                                                      metrics:nil
                                                                        views:views]];
    
    
    [self setupButtons];
    [self updateButtons];
    
}

- (NSArray *)onlyPdfsAndFoldersInItems:(NSArray *)items
{
    NSMutableArray *filteredItems = [[NSMutableArray alloc] init];
    for (GTLDriveFile *file in items) {
        if ([file.mimeType isEqualToString:@"application/pdf"] || [file.mimeType isEqualToString:@"application/vnd.google-apps.folder"]) {
            [filteredItems addObject:file];
        }
    }
    return filteredItems;
}


// When the view appears, ensure that the Drive API service is authorized, and perform API calls.
- (void)viewDidAppear:(BOOL)animated
{
    UIViewController *authVC=[self.manager authorisationViewController];
    
    if (authVC)
    {
        // Not yet authorized, request authorization by pushing the login UI onto the UI stack.
        UINavigationController *nc=(UINavigationController *)[self parentViewController];
        [nc pushViewController:authVC animated:YES];
        
    }
    else
    {
        [self getFiles];
    }
}

-(void)cancel:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)signOut:(id)sender
{
    [GTMOAuth2ViewControllerTouch removeAuthFromKeychainForName:kKeychainItemName];
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(void)getFiles
{
    if (self.table.pullToRefreshView.state==SVPullToRefreshStateStopped)
    {
        [self.table triggerPullToRefresh];
    }
    
    self.manager.sharedWithMe=self.showShared;
    self.fileList=NULL;
    
    [self updateDisplay];
    [self updateButtons];
    
    [self.manager fetchFilesWithCompletionHandler:^(GTLServiceTicket *ticket, GTLDriveFileList *fileList, NSError *error)
     {
         [self.table.pullToRefreshView stopAnimating];
         
         
         if (error)
         {
             NSString *message=[NSString stringWithFormat:@"Error: %@",error.localizedDescription ];
             [self.output setText:message];
         }
         else
         {
             self.fileList=fileList;
         }
         
         [self updateDisplay];
         
     }];
}

-(void)updateDisplay
{
    [self updateButtons];
    
    if (self.fileList)
    {
        if ([self onlyPdfsAndFoldersInItems:self.fileList.files].count)
        {
            [self.table setHidden:NO];
            [self.table reloadData];
        }
        else
        {
            [self.output setText:@"Folder is empty"];
            [self.table setHidden:YES];
        }
    }
}

-(void)setupButtons
{
    NSArray *segItemsArray = [NSArray arrayWithObjects: @"Mine",@"Shared", nil];
    UISegmentedControl *segmentedControl = [[UISegmentedControl alloc] initWithItems:segItemsArray];
    
    
    UIBarButtonItem *closeButton=[[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStylePlain target:self action:@selector(cancel:)];
    [closeButton setTitleTextAttributes:@{NSFontAttributeName: [UIFont fontWithName:@"HelveticaNeue-Medium" size:18.0], NSKernAttributeName: @2.0} forState:UIControlStateNormal];
    
    self.upItem=[[UIBarButtonItem alloc] initWithTitle:@"Back" style:UIBarButtonItemStylePlain target:self action:@selector(up:)];
    [self.upItem setTitleTextAttributes:@{NSFontAttributeName: [UIFont fontWithName:@"HelveticaNeue-Medium" size:16.0], NSKernAttributeName: @2.0} forState:UIControlStateNormal];
    
    // This should eventually sign you out of Google.
    [self.navigationItem setLeftBarButtonItem:closeButton
                                     animated:YES];
    UIBarButtonItem *signOutButton = [[UIBarButtonItem alloc] initWithTitle:@"Sign Out" style:UIBarButtonItemStylePlain target:self action:@selector(signOut:)];
    [signOutButton setTitleTextAttributes:@{NSFontAttributeName: [UIFont fontWithName:@"HelveticaNeue-Medium" size:18.0], NSKernAttributeName: @2.0} forState:UIControlStateNormal];
    [self.navigationItem setRightBarButtonItem:signOutButton];
}

-(void)updateButtons
{
    UIBarButtonItem *flex=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                        target:nil
                                                                        action:nil];
    
    if ([self.folderTrail count]>1 && !self.showShared)
    {
        [self.toolbar setItems:@[self.upItem,flex] animated:YES];
    }
    else
    {
        [self.toolbar setItems:@[flex] animated:YES];
    }
}

#pragma mark searching

-(void)mineSharedChanged:(UISegmentedControl*)sender
{
    self.showShared=([sender selectedSegmentIndex]==1);
    
    [self getFiles];
}

-(void)up:(id)sender
{
    if ([self.folderTrail count]>1)
    {
        [self.folderTrail removeLastObject];
        [self.manager setFolderId:self.folderTrail.lastObject];
        [self getFiles];
    }
}

-(void)openFolder:(GTLDriveFile *)file
{
    NSString *folderId=[file identifier];
    NSString *currentFolder=[self.folderTrail lastObject];
    
    if ([folderId isEqualToString:currentFolder])
    {
        return;
    }
    
    else
    {
        [self.folderTrail addObject:folderId];
        [self.manager setFolderId:file.identifier];
        [self getFiles];
    }
}



#pragma mark table

-(GTLDriveFile*)fileForIndexPath:(nonnull NSIndexPath *)indexPath
{
    NSArray *filteredFiles = [self onlyPdfsAndFoldersInItems:self.fileList.files];
    if (filteredFiles.count) {
        return [filteredFiles objectAtIndex:[indexPath row]];
    }
    return nil;
}


-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [[self onlyPdfsAndFoldersInItems:self.fileList.files] count];
}

-(UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(nonnull NSIndexPath *)indexPath
{
    NSString *identifier=@"HSDriveFileViewer";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell)
    {
        cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
        
        UIImageView *iv=cell.imageView;
        [iv setImage:self.blankImage];
        
        AsyncImageView *async=[[AsyncImageView alloc] initWithFrame:CGRectMake(0, 0, 40, 40)];
        [async setContentMode:UIViewContentModeCenter];
        
        [iv addSubview:async];
    }
    
    AsyncImageView *async=(AsyncImageView *)[cell.imageView.subviews firstObject];
    GTLDriveFile *file=[self fileForIndexPath:indexPath];
    
    if (file)
    {
        [cell.textLabel setText:file.name];
        [cell.textLabel setFont:[UIFont fontWithName:@"HelveticaNeue" size:16]];
        [async setImageURL:[NSURL URLWithString:file.iconLink]];
    }
    else
    {
        [cell.textLabel setText:NULL];
        [async setImage:NULL];
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    GTLDriveFile *file=[self fileForIndexPath:indexPath];
    NSLog(@"FILE: %@", file.name);
    if ([file isFolder])
    {
        [self openFolder:file];
    }
    else
    {
        [self dismissViewControllerAnimated:YES
                                 completion:^{
                                     self.completion(self.manager,file);
                                 }];
    }
}



@end