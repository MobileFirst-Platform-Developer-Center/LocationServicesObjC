/**
* Copyright 2015 IBM Corp.
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
* http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

#import "DemoAppViewController.h"

@interface DemoAppViewController () // private methods and properties
@property (weak, nonatomic) IBOutlet UILabel *timestamp;
@property (weak, nonatomic) IBOutlet UILabel *lonLabel;
@property (weak, nonatomic) IBOutlet UILabel *latLabel;
@property (weak, nonatomic) IBOutlet UIButton *button;

- (IBAction)buttonClicked:(id)sender;
- (void) doDisplayPosition: (WLGeoPosition*) pos;
- (void) acquireLocation;
- (void) displayPosition: (WLGeoPosition*) pos;
- (void) displayAlert: (NSString*) msg;
- (void) displayGeoErrorMessage: (WLGeoError*) error;
@end

@implementation DemoAppViewController

NSString* start = @"Start Acquisition";
NSString* stop = @"Stop Acquisition";

- (void)viewDidLoad {
    
    [super viewDidLoad];
    self.title = @"Location Services";
}

-(id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    
    if (!self) {
        return nil;
    }
    
    [[WLClient sharedInstance]wlConnectWithDelegate:self];
    
    return self;
}

- (IBAction)buttonClicked:(id)sender {
    if ([[self.button titleForState:UIControlStateNormal] isEqual:start]) {
        [self acquireLocation];
        [self.button setTitle:stop forState: UIControlStateNormal];
    }
    else {
        [[[WLClient sharedInstance] getWLDevice] stopAcquisition];
        [self.button setTitle:start forState:UIControlStateNormal];
    }
}

- (void)acquireLocation{
    // use GPS to get the user's location
    WLGeoAcquisitionPolicy* geoPolicy = [WLGeoAcquisitionPolicy getLiveTrackingProfile];
    [geoPolicy setTimeout:10000]; // set timeout to 1 minute
    [geoPolicy setMaximumAge: 10000]; // allow to use a position that is 10 seconds old
    
    id<WLDevice> wlDevice = [[WLClient sharedInstance] getWLDevice];
    // get the user's current position
    [wlDevice acquireGeoPositionWithDelegate:[WLCallbackFactory createGeoCallback:^(WLGeoPosition* pos) {
        // first, display the acquired position
        [self displayPosition: pos];
        
        // now, set-up configuration for ongoing acquisition
        WLLocationServicesConfiguration* config = [[WLLocationServicesConfiguration alloc] init];
        
        // 1. Acquisition Policy (same one that is used for the one-time acquisition)
        WLAcquisitionPolicy* policy = [[WLAcquisitionPolicy alloc] init];
        [policy setGeoPolicy: geoPolicy];
        [config setPolicy:policy];
        
        
        // 2. Triggers
        WLTriggersConfiguration* triggers = [[WLTriggersConfiguration alloc] init];
        
        WLGeoPositionChangeTrigger* changeTrigger = [[WLGeoPositionChangeTrigger alloc] init];
        [changeTrigger setCallback: [WLCallbackFactory createTriggerCallback:^(id<WLDeviceContext> deviceContext) {
            [self displayPosition: [deviceContext getGeoPosition]];
        }]];
        [[triggers getGeoTriggers] setObject: changeTrigger forKey:@"posChange"];
        
        WLGeoExitTrigger* exitArea = [[WLGeoExitTrigger alloc] init];
        [exitArea setArea: [[WLCircle alloc] initWithCenter:[pos getCoordinate] radius:200]];
        [exitArea setCallback:[WLCallbackFactory createTriggerCallback:^(id<WLDeviceContext> deviceContext) {
            [self displayAlert: @"Left the area"];
            NSMutableDictionary* event = [NSMutableDictionary dictionaryWithObject:@"exit area" forKey:@"event"];
            [[WLClient sharedInstance] transmitEvent:event immediately:YES];
        }]];
        [[triggers getGeoTriggers] setObject: exitArea forKey:@"leftArea"];
        
        WLGeoDwellInsideTrigger* dwellInArea = [[WLGeoDwellInsideTrigger alloc] init];
        [dwellInArea setArea:[[WLCircle alloc] initWithCenter:[pos getCoordinate] radius:50]];
        [dwellInArea setDwellingTime:3000];
        [dwellInArea setCallback:[WLCallbackFactory createTriggerCallback:^(id<WLDeviceContext> deviceContext) {
            [self displayAlert: @"Still in the vicinity"];
            NSMutableDictionary* event = [NSMutableDictionary dictionaryWithObject:@"dwell inside area" forKey:@"event"];
            [[WLClient sharedInstance] transmitEvent:event immediately:YES];
        }]];
        [[triggers getGeoTriggers] setObject:dwellInArea forKey:@"dwellArea"];
        
        
        [config setTriggers:triggers];
        
        // 3.  Failure callbacks (add Geo callback)
        WLAcquisitionFailureCallbacksConfiguration* failureCallbacks = [[WLAcquisitionFailureCallbacksConfiguration alloc] init];
        [failureCallbacks setGeoFailureCallback:[WLCallbackFactory createGeoFailureCallback:^(WLGeoError *error) {
            [self displayGeoErrorMessage: error];
        }]];
        [[config getFailureCallbacks] addObject:failureCallbacks];
        
        // start
        [wlDevice startAcquisition:config];
        
    }]
    failureDelegate:[WLCallbackFactory createGeoFailureCallback:^(WLGeoError *error) {
        [self displayGeoErrorMessage: error];
        [self.button setTitle:start forState:UIControlStateNormal];
    }]
    policy: geoPolicy];

}

- (void) displayAlert: (NSString*) msg {
    UIAlertView* alertView = [[UIAlertView alloc]
       initWithTitle:@""
       message:msg
       delegate:self
       cancelButtonTitle:@"Ok"
       otherButtonTitles: nil];
    [alertView performSelectorOnMainThread:@selector(show) withObject:nil waitUntilDone:NO];
}

- (void) displayPosition: (WLGeoPosition*) pos {
    [self performSelectorOnMainThread:@selector(doDisplayPosition:) withObject:pos waitUntilDone:NO];
}


- (void) doDisplayPosition: (WLGeoPosition*) pos {
    [self.latLabel setText:[NSString stringWithFormat:@"%f",[[pos getCoordinate] getLatitude]]];
    [self.lonLabel setText:[NSString stringWithFormat:@"%f",[[pos getCoordinate] getLongitude]]];
    [self.timestamp setText:[[NSDate dateWithTimeIntervalSince1970:[[pos getTimestamp] longLongValue] / 1000 ] description]  ];
}

- (void) displayGeoErrorMessage: (WLGeoError*) error {
    [self displayAlert : [NSString stringWithFormat:@"Error acquiring geo (%d): %@", [error getErrorCode], [error getMessage]]];

}

-(void)onSuccess:(WLResponse *)response {
    
}

-(void)onFailure:(WLFailResponse *)response {
    [self displayAlert:response.errorMsg];
}


@end
