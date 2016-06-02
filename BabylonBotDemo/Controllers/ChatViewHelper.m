
#import "ChatViewHelper.h"
#import "BBConstants.h"
#import "ApiManagerChatBot.h"
#import "JSQViewMediaItem.h"
#import "OptionsTableViewController.h"
#import "BBOption.h"
#import "RatingView.h"
@import ios_maps;

@interface ChatViewHelper () <OptionsDelegate, RatingViewDelegate>
@end

@implementation ChatViewHelper

- (void)viewDidLoad {
    [super viewDidLoad];
    
    //TODO: Set UserID + DisplayName
    self.chatMessagesArray = [[NSMutableArray alloc] init];
    self.senderId = @"123456789";
    self.senderDisplayName = @"Anonymous User";
    
    // Setup WebSockets
    [self setPubNubClient:[BBPubNubClient shared]];
    [self.pubNubClient setPubNubClientDelegate:self];
    
    //TODO: Replace the channel id with user id
    [self.pubNubClient subscribeToChannel:kChatBotApiUserId completionHandler:^(PNAcknowledgmentStatus *status) {
        [self.pubNubClient pingPubNubService:^(PNErrorStatus *status, PNTimeResult *result) {
            if (!status.isError) {
                //TODO: Handle if push notifications is disabled ()
                // Start chatBot
                [[ApiManagerChatBot sharedConfiguration] postConversationText:@"hello" success:^(AFHTTPRequestOperation *operation, id response) {
                    // post conversation and wait websockets response
                } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                    JSQMessage *message = [JSQMessage messageWithSenderId:kBabylonDoctorId displayName:kBabylonDoctorName text:[NSString babylonErrorMsg:error]];
                    [self addChatMessageForBot:message showObject:YES];
                    
                }];
                
            }
        }];
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

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Enable/disable springy bubbles
    self.collectionView.collectionViewLayout.springinessEnabled = YES;
    [self.collectionView reloadData];
    
}

- (void)customAction:(id)sender {
    NSLog(@"Custom action received! Sender: %@", sender);
}

-(BOOL)showTypingIndicator {
    BOOL showTypingIndicator = [super showTypingIndicator];
    self.toolbarButtonsEnabled = !showTypingIndicator;
    return showTypingIndicator;
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
            [self showChatBotOptions:nil inOptions:chatDataModel.optionData.options
                     forQuestion:chatDataModel senderId:kBabylonDoctorId
               senderDisplayName:kBabylonDoctorName date:[NSDate date]];
        } else {
            [self addChatMessageForBot:botMessage showObject:YES];
        }
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        JSQMessage *message = [JSQMessage messageWithSenderId:kBabylonDoctorId displayName:kBabylonDoctorName text:[NSString babylonErrorMsg:error]];
        [self addChatMessageForBot:message showObject:YES];
    }];
    
}

- (void)pubNubClient:(PubNub *)client didReceiveStatus:(PNSubscribeStatus *)status {
    NSLog(@"PubNub Client: %@ \n Status: %@ \n Channels: %@", client, status, status.subscribedChannels);
}

- (void)showChatBotOptions:(BBChatBotDataModelChosenOption *)selectedOption inOptions:(NSArray *)options forQuestion:(BBChatBotDataModelStatement *)question senderId:(NSString *)senderId senderDisplayName:(NSString *)senderDisplayName date:(NSDate *)date {
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
        
        [dataSource addObject:[BBOption optionWithText:option.value textColor:textColor font:[UIFont babylonRegularFont:kDefaultFontSize] backgroundColor:backgroundColor height:kOptionCellHeight optionSelected:selectedOption]];
    }
    
    OptionsTableViewController *viewController = [[OptionsTableViewController alloc] initWithDataSource:dataSource];
    viewController.delegate = self;
    JSQViewMediaItem *item = [[JSQViewMediaItem alloc] initWithViewControllerMedia:viewController];
    JSQMessage *userMessage = [JSQMessage messageWithSenderId:senderId
                                                  displayName:senderDisplayName
                                                         text:question.value
                                                        media:item];
    userMessage.wantsTouches = YES;
    [self addChatMessageForBot:userMessage showObject:YES];
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
        
        //FIXME: randomly shows rating. This should come from the socket
        NSInteger rand = arc4random_uniform(3);
        if(rand == 2) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                __weak typeof(self) weakSelf = self;
                [[ApiManagerChatBot sharedConfiguration] receiveRatingRequestFromSocketSuccess:^(AFHTTPRequestOperation *operation, id response) {
                    __strong typeof(self) strongSelf = weakSelf;
                    if(!strongSelf) {
                        return;
                    }
                    [strongSelf addRating:3];
                } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                    NSLog(@"%@", error);
                }];
            });
        }

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

-(void)sendRating:(NSInteger)rating completionHandler:(void(^)(BOOL success))completionHandler {
    //FIXME: hardcoded conversationId
    [[ApiManagerChatBot sharedConfiguration] postConversationRating:rating withConversationId:@"1" success:^(AFHTTPRequestOperation *operation, id response) {
        if(completionHandler) {
            completionHandler(YES);
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        if(completionHandler) {
            completionHandler(NO);
        }
    }];
}

- (void)sendFakeData:(void(^)()) completionHandler {
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

- (void)addRating:(NSInteger)rating {
    RatingView *view = [[RatingView alloc] initWithNumberOfButtons:5 maxWidth:self.view.bounds.size.width - 100.f initialRating:rating];
    view.delegate = self;
    JSQViewMediaItem *item = [[JSQViewMediaItem alloc] initWithViewMedia:view];
    JSQMessage *userMessage = [JSQMessage messageWithSenderId:kBabylonDoctorId
                                                  displayName:kBabylonDoctorName
                                                         text:@"How would you rate my service?"
                                                        media:item];
    view.message = userMessage;
    userMessage.wantsTouches = YES;
    [self addChatMessageForUser:userMessage showObject:YES];
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

#pragma mark - OptionsDelegate

-(void)sender:(id)sender selectedOption:(BBOption *)option {
    NSLog(@"OPTION SELECTED");
}

#pragma mark - RatingViewDelegate

-(void)ratingView:(RatingView *)ratingView selectedRating:(NSInteger)rating {
    ratingView.userInteractionEnabled = NO;
    ratingView.message.wantsTouches = NO;
    [self.collectionView reloadData];
   
    self.showTypingIndicator = YES;
    
    __weak typeof(self) weakSelf = self;
    [self sendRating:rating completionHandler:^(BOOL success) {
        __strong typeof(self) strongSelf = weakSelf;
        if(!strongSelf) {
            return;
        }
        
        strongSelf.showTypingIndicator = NO;

        if(success) {
            NSLog(@"SENT RATING (%ld)", rating);
            
            JSQMessage *userMessage = [JSQMessage messageWithSenderId:kBabylonDoctorId
                                                          displayName:kBabylonDoctorName
                                                                 text:@"Thanks for the feedback"];
            [strongSelf addChatMessageForUser:userMessage showObject:YES];
        }
    }];
}

@end