
#import "ChatViewHelper.h"
#import "BBConstants.h"
#import "ApiManagerChatBot.h"
#import "JSQViewMediaItem.h"
#import "OptionsTableViewController.h"
#import "BBOption.h"
@import ios_maps;

@interface ChatViewHelper () <JSQMessagesOptionsDelegate>

@end

@implementation ChatViewHelper

- (void)viewDidLoad {
    [super viewDidLoad];
    
    //TODO: Set UserID + DisplayName
    self.chatMessagesArray = [[NSMutableArray alloc] init];
    self.senderId = @"123456789";
    self.senderDisplayName = @"Anonymous User";
    
    // Setup WebSockets
    [self setPubNubClient:[[BBPubNubClient alloc] init]];
    [self.pubNubClient setPubNubClientDelegate:self];
    
    //TODO: Replace the channel id with user id
    [self.pubNubClient subscribeToChannel:@"1077"];
    [self.pubNubClient pingPubNubService:^(PNErrorStatus *status, PNTimeResult *result) {
        if (!status.isError) {
            
            // Start chatBot
            [[ApiManagerChatBot sharedConfiguration] postConversationText:@"hello" success:^(AFHTTPRequestOperation *operation, id response) {
                BBChatBotDataModelV2 *chatDataModel = [[BBChatBotDataModelV2 alloc] initWithDictionary:response];
                NSLog(@"conversation id > %@ - %@", chatDataModel.conversationId, chatDataModel.statements);
                
            } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                JSQMessage *message = [JSQMessage messageWithSenderId:kBabylonDoctorId displayName:kBabylonDoctorName text:[NSString babylonErrorMsg:error]];
                [self addChatMessageForBot:message showObject:YES];
                
            }];
            
        }
    }];
    
    // Custom config for chat
    self.inputToolbar.contentView.textView.pasteDelegate = self;
    self.collectionView.collectionViewLayout.incomingAvatarViewSize = CGSizeMake(30, 30);
    self.collectionView.collectionViewLayout.outgoingAvatarViewSize = CGSizeZero;
    self.showTypingIndicator = YES;
    self.showLoadEarlierMessagesHeader = NO;
    self.inputToolbar.maximumHeight = 150;
    
    JSQMessagesBubbleImageFactory *bubbleFactory = [[JSQMessagesBubbleImageFactory alloc] init];
    self.userBubbleMsg = [bubbleFactory outgoingMessagesBubbleImageWithColor:[UIColor babylonPurple]];
    self.botBubbleMsg = [bubbleFactory incomingMessagesBubbleImageWithColor:[UIColor groupTableViewBackgroundColor]];
    
    [JSQMessagesCollectionViewCell registerMenuAction:@selector(customAction:)];
    [UIMenuController sharedMenuController].menuItems = @[ [[UIMenuItem alloc] initWithTitle:@"Edit" action:@selector(customAction:)] ];
    [JSQMessagesCollectionViewCell registerMenuAction:@selector(delete:)];
    
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    // Enable/disable springy bubbles
    self.collectionView.collectionViewLayout.springinessEnabled = YES;
}

- (void)customAction:(id)sender {
    NSLog(@"Custom action received! Sender: %@", sender);
}

#pragma mark - PubNubClient delegate
- (void)pubNubClient:(PubNub *)client didReceiveMessage:(PNMessageResult *)message {
    
    //TODO:
    NSString *statementId = [message.data.message objectForKey:@"statement"];
    NSString *chatId = [message.data.message objectForKey:@"conversation"];
    
    [[ApiManagerChatBot sharedConfiguration] getConversationStatement:statementId withConversationId:chatId sucess:^(AFHTTPRequestOperation *operation, id response) {
        
        BBChatBotDataModelStatement *chatDataModel = [[BBChatBotDataModelStatement alloc] initWithDictionary:response];
        JSQMessage *botMessage = [[JSQMessage alloc] initWithSenderId:kBabylonDoctorId
                                                    senderDisplayName:kBabylonDoctorName
                                                                 date:[NSDate date]
                                                                 text:chatDataModel.value];
        
        if ([chatDataModel.optionData.options count]>0) {
            [self presentMenuOptionsController:chatDataModel];
            [self addChatMessageForBot:botMessage showObject:NO];
        } else {
            [self addChatMessageForBot:botMessage showObject:YES];
        }
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        JSQMessage *message = [JSQMessage messageWithSenderId:kBabylonDoctorId displayName:kBabylonDoctorName text:[NSString babylonErrorMsg:error]];
        [self addChatMessageForBot:message showObject:YES];
    }];
    
}

- (void)pubNubClient:(PubNub *)client didReceiveStatus:(PNSubscribeStatus *)status {
    NSLog(@"PubNub Client: %@ - status: %@ / %@", client, status, status.subscribedChannels);
}

#pragma mark - Menu options
- (void)presentMenuOptionsController:(BBChatBotDataModelStatement *)chatDataModel {
    
    UIAlertController *alertViewController = [UIAlertController alertControllerWithTitle:nil
                                                                                 message:NSLocalizedString(chatDataModel.value, nil)
                                                                          preferredStyle:UIAlertControllerStyleActionSheet];
    
    for (int x=0; x<[chatDataModel.optionData.options count]; x++) {
        
        NSString *optionTitle = [(BBChatBotDataModelChosenOption *)[chatDataModel.optionData.options objectAtIndex:x] value];
        UIAlertAction *chatMenuOption = [UIAlertAction actionWithTitle:NSLocalizedString(optionTitle, nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            BBChatBotDataModelChosenOption *optionSelected = chatDataModel.optionData.options[x];
            
            //TODO:
            //            [self sendOption:@{@"options":@[@{@"id":optionSelected.messageId,
            //                                              @"value":optionSelected.value,
            //                                              @"source":optionSelected.source}]} withConversationId:chatDataModel.inResponseTo completionHandler:^(bool success) {
            //                [self selectedOption:chatDataModel.optionData.options[x] inOptions:chatDataModel.optionData.options forQuestion:chatDataModel senderId:kBabylonDoctorId senderDisplayName:kBabylonDoctorName date:[NSDate date]];
            //            }];
            
            [self sendMessage:nil withMessageText:optionTitle senderId:self.senderId senderDisplayName:self.senderDisplayName date:[NSDate date] showMessage:NO success:^{
                [self selectedOption:optionSelected inOptions:chatDataModel.optionData.options forQuestion:chatDataModel senderId:kBabylonDoctorId senderDisplayName:kBabylonDoctorName date:[NSDate date]];
            }];
        }];
        [alertViewController addAction:chatMenuOption];
    }
    
    UIAlertAction *cancelMenuOption = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                                               style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                                                                   
                                                               }];
    
    [alertViewController addAction:cancelMenuOption];
    
    
    __strong typeof(self) strongSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [strongSelf presentViewController:alertViewController animated:YES completion:nil];
    });
    
}

- (void)selectedOption:(BBChatBotDataModelChosenOption *)selectedOption inOptions:(NSArray *)options forQuestion:(BBChatBotDataModelStatement *)question senderId:(NSString *)senderId senderDisplayName:(NSString *)senderDisplayName date:(NSDate *)date {
    NSMutableArray *dataSource = [NSMutableArray new];
    
    for(BBChatBotDataModelChosenOption *option in options ) {
        UIColor *textColor;
        UIColor *backgroundColor;
        if(option == selectedOption) {
            backgroundColor = [UIColor babylonPurple];
            textColor = [UIColor babylonWhite];
        } else {
            backgroundColor = [UIColor babylonWhite];
            textColor = [UIColor babylonPurple];
        }
        
        [dataSource addObject:[BBOption optionWithText:option.value textColor:textColor font:[UIFont babylonRegularFont:kDefaultFontSize] backgroundColor:backgroundColor height:kOptionCellHeight]];
    }

    OptionsTableViewController *viewController = [[OptionsTableViewController alloc] initWithDataSource:dataSource];
    viewController.delegate = self;
    JSQViewMediaItem *item = [[JSQViewMediaItem alloc] initWithViewControllerMedia:viewController];
    JSQMessage *userMessage = [JSQMessage messageWithSenderId:senderId
                                                  displayName:senderDisplayName
                                                         text:question.value
                                                        media:item];
    userMessage.wantsTouches = YES;
    [self addChatMessageForUser:userMessage showObject:YES];
}

- (void)sendMessage:(UIButton *)button withMessageText:(NSString *)text senderId:(NSString *)senderId senderDisplayName:(NSString *)senderDisplayName date:(NSDate *)date showMessage:(BOOL)showMessage success:(ChatViewHelperSendSuccess)success {
    
    JSQMessage *userMessage = [[JSQMessage alloc] initWithSenderId:senderId
                                                 senderDisplayName:senderDisplayName
                                                              date:date
                                                              text:text];
    
    [self addChatMessageForUser:userMessage showObject:showMessage];
    
    self.showTypingIndicator = YES;
    [self.collectionView reloadData];
    [self scrollToBottomAnimated:YES];
    
    //FIXME: DEBUG ONLY
    [[ApiManagerChatBot sharedConfiguration] postConversationText:text success:^(AFHTTPRequestOperation *operation, id response) {
        BBChatBotDataModelV2 *chatDataModel = [[BBChatBotDataModelV2 alloc] initWithDictionary:response];
        if(success) {
            success();
        }
        NSLog(@"conversation id > %@ - %@", chatDataModel.conversationId, chatDataModel.statements);
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        JSQMessage *message = [JSQMessage messageWithSenderId:kBabylonDoctorId displayName:kBabylonDoctorName text:[NSString babylonErrorMsg:error]];
        [self addChatMessageForBot:message showObject:YES];
    }];

    
}

- (void)sendOption:(NSDictionary *)optionDic withConversationId:(NSString *)conversationId
 completionHandler:(void(^)(bool success))completionHandler {
    
    [[ApiManagerChatBot sharedConfiguration] postConversationOption:optionDic withConversationId:conversationId success:^(AFHTTPRequestOperation *operation, id response) {
        completionHandler(YES);
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        completionHandler(NO);
    }];
    
}

#pragma mark - Media Picker
- (void)didPressAccessoryButton:(UIButton *)sender {
    [self.inputToolbar.contentView.textView resignFirstResponder];
    
    UIAlertController *alertViewController = [UIAlertController alertControllerWithTitle:@"Media Messages"
                                                                                 message:nil
                                                                          preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alertViewController addAction:[UIAlertAction actionWithTitle:@"Send photo" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self choosePortraitPhoto];
    }]];
    
    [alertViewController addAction:[UIAlertAction actionWithTitle:@"Send location" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        __weak typeof(self) weakSelf = self;
        [self addLocation:^{
            [weakSelf.collectionView reloadData];
        }];
    }]];
    
    [alertViewController addAction:[UIAlertAction actionWithTitle:@"Send video" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        //HARDCODE:
        [self addVideo:[NSURL URLWithString:@"file://"]];
    }]];
    
    [alertViewController addAction:[UIAlertAction actionWithTitle:@"Send audio" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        //HARDCODE:
        [self addAudio: [[NSBundle mainBundle] pathForResource:@"sample" ofType:@"m4a"]];
    }]];
    
    [alertViewController addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        //DO NOTHING
    }]];
    
    __strong typeof(self) strongSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [strongSelf presentViewController:alertViewController animated:YES completion:nil];
    });
    
}

- (void)choosePortraitPhoto {
    UIImagePickerController * picker = [[UIImagePickerController alloc] init];
    [picker setDelegate:self];
    [picker setSourceType:(UIImagePickerControllerSourceTypePhotoLibrary)];
    [self presentViewController:picker animated:YES completion:^{}];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    [picker dismissViewControllerAnimated:NO completion:^{
        [UIView animateWithDuration:1.0f animations:^{
            UIImage *imageSelected = (UIImage *) [info objectForKey:UIImagePickerControllerOriginalImage];
            [self addPhoto:imageSelected];
        }];
    }];
}

- (void)addPhoto:(UIImage *)image {
    JSQPhotoMediaItem *photoItem = [[JSQPhotoMediaItem alloc] initWithImage:image];
    JSQMessage *photoMessage = [JSQMessage messageWithSenderId:self.senderId
                                                   displayName:self.senderDisplayName
                                                         media:photoItem];
    [self addChatMessageForUser:photoMessage showObject:YES];
}

- (void)addLocation:(JSQLocationMediaItemCompletionBlock)completion {
    
    //TODO: It's not stable yet (Review it)
    BBLocationManager *locationManager = [BBLocationManager sharedInstance];
    [locationManager startUpdatingLocation];
    
    JSQLocationMediaItem *locationItem = [[JSQLocationMediaItem alloc] init];
    [locationItem setLocation:locationManager.locationManager.location withCompletionHandler:completion];
    
    JSQMessage *locationMessage = [JSQMessage messageWithSenderId:self.senderId
                                                      displayName:self.senderDisplayName
                                                            media:locationItem];
    [self addChatMessageForUser:locationMessage showObject:YES];
    
}

- (void)addAudio:(NSString *)sample {
    
    NSData * audioData = [NSData dataWithContentsOfFile:sample];
    JSQAudioMediaItem *audioItem = [[JSQAudioMediaItem alloc] initWithData:audioData];
    JSQMessage *audioMessage = [JSQMessage messageWithSenderId:self.senderId
                                                   displayName:self.senderDisplayName
                                                         media:audioItem];
    [self addChatMessageForUser:audioMessage showObject:YES];
}

- (void)addVideo:(NSURL *)videoURL {
    
    JSQVideoMediaItem *videoItem = [[JSQVideoMediaItem alloc] initWithFileURL:videoURL isReadyToPlay:YES];
    JSQMessage *videoMessage = [JSQMessage messageWithSenderId:self.senderId
                                                   displayName:self.senderDisplayName
                                                         media:videoItem];
    [self addChatMessageForUser:videoMessage showObject:YES];
    
}

- (void)addChatMessageForUser:(JSQMessage *)message showObject:(BOOL)showObject {
    [JSQSystemSoundPlayer jsq_playMessageSentSound];
    if (showObject) {
        [self.chatMessagesArray addObject:message];
    }
    [self finishSendingMessageAnimated:YES];
}

- (void)addChatMessageForBot:(JSQMessage *)message showObject:(BOOL)showObject {
    [JSQSystemSoundPlayer jsq_playMessageReceivedSound];
    if (showObject) {
        [self.chatMessagesArray addObject:message];
        [[[[self tabBarController] tabBar] items][0] setBadgeValue:[NSString babylonBadgeCounter:self.chatMessagesArray]];
    }
    [self finishReceivingMessageAnimated:YES];
}

- (BOOL)composerTextView:(JSQMessagesComposerTextView *)textView shouldPasteWithSender:(id)sender {
    return YES;
}

#pragma mark - JSQMessagesOptionsDelegate

-(void)sender:(id)sender selectedOption:(BBOption *)option {
    NSLog(@"OPTION SELECTED");
}

@end