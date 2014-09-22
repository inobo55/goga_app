//
//  ViewController.m
//
//  Created by inobo52 on 2014/09/19.
//  Copyright (c) 2014年 goga_ino. All rights reserved.
//
//http://iosguy.com/tag/directions-api/
//https://developers.google.com/maps/documentation/directions/?hl=ja#UnitSystems
//https://developers.google.com/maps/documentation/directions/?hl=ja#Audience
//https://developers.google.com/maps/documentation/geocoding/?hl=ja
//https://developers.google.com/maps/documentation/ios/?hl=ja
//http://kosoku.jp/api.php
//http://dev.classmethod.jp/smartphone/iphone/ios-map-programming-series-1/

//

#import "ViewController.h"

@interface ViewController() 
@property GMSMapView *mapView_;
@property NSArray *path;
@property NSArray *steps;
@property GMSMarker *marker;
@property NSInteger time_count;
@property NSInteger index_path;
@property NSInteger index_step;
@property NSArray *mileStoneIndexes;
@property NSInteger coordinate_diff;

@property YTPlayerView *playerView;
@end

@implementation ViewController

//http://iosguy.com/tag/directions-api/
//http://qiita.com/jtemplej/items/42e50ae30214ffcd80ae
- (void)googleMapAPI{
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    NSString *origin = @"東京都調布市";
    NSString *dest = @"兵庫県神戸市中央区相生町三丁目";
    origin = [origin stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]];
    dest = [dest stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]];
    NSString *url = [NSString stringWithFormat:@"http://maps.googleapis.com/maps/api/directions/json?origin=%@&destination=%@&sensor=false",origin,dest];
    [manager GET:url
      parameters:nil
         success:^(AFHTTPRequestOperation *operation, id responseObject) {
             // 通信に成功した場合の処理
             [self parseResponse:responseObject];
         }
         failure:^(AFHTTPRequestOperation *operation, NSError *error) {
             // エラーの場合はエラーの内容をコンソールに出力する
             NSLog(@"Error: %@", error);
         }];
}

-(void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:YES];
    [self googleMapAPI];
    _time_count=0;
    _index_step=0;
    _index_path=1;
}

//マップ設置&タイマー
- (void)viewDidLoad
{
    [super viewDidLoad];
    GMSCameraPosition *camera = [GMSCameraPosition cameraWithLatitude:35.70171 longitude:139.580297 zoom:7];
    _mapView_ = [GMSMapView mapWithFrame:CGRectZero camera:camera];
    _mapView_.myLocationEnabled = YES;
    self.view = _mapView_;
    
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(moveMarker:)
                                                    userInfo:_marker repeats:YES];
    [timer fire];
    
    _playerView = [[YTPlayerView alloc]init];
    _playerView.frame = CGRectMake(0,0,320,155);
    NSDictionary *playerVars = @{
                                 @"playsinline" : @1,
                                 };
    [self.playerView loadWithVideoId:@"M7lc1UVf-VE" playerVars:playerVars];
    _playerView.delegate = self;
    [_mapView_ addSubview:_playerView];
    
}

-(void)moveMarker:(NSTimer*)timer{

    //現在地==目的地 then 次の目的地に変更 else そのまま移動
    
    if(!_steps) return;
    
    if(_index_path >= _path.count){
        _marker.snippet = @"END";
        return;
    }
    _time_count++;
    
    if(_time_count>10)[_playerView playVideo];

    //_pathの中で何番目が_stepsの何番目に対応しているかわからん．=>わかると，複数のpath:運転時間の対応が可能．
    //_stepsのstart_point==_pathのlat&lonが一致すれば，そこが対応
    //if end_point == dest_lat&lon => step_count++;
    
    CLLocation *dest = _path[_index_path];
    float destLat = dest.coordinate.latitude;
    float destLon = dest.coordinate.longitude;
    float markLat = _marker.position.latitude;
    float markLon = _marker.position.longitude;
    
    //マークと中間目的地が近ければindex_path++
    float diff = _coordinate_diff;
    if(destLat+diff>=markLat&&markLat>=destLat-diff && destLon+diff>=markLon&&markLon>=destLon-diff)
        _index_path++;
    //時間が十分に経過していればindex_step++
    NSDictionary *step = _steps[_index_step];
    NSNumber* duration = [[step objectForKey:@"duration"] objectForKey:@"value"];
    if(_time_count==duration.intValue){
        _index_step++;
        _time_count=0;
    }
    double pathCount_step = [_mileStoneIndexes[_index_step] intValue];
    double path_duration = duration.doubleValue / pathCount_step;
    float diff_lat = destLat - markLat;
    float diff_lon = destLon - markLon;
   // _marker.position = CLLocationCoordinate2DMake(markLat+diff_lat/path_duration,markLon+diff_lon/path_duration);
    _marker.position = CLLocationCoordinate2DMake(markLat+diff_lat,markLon+diff_lon);
    _marker.snippet = @"移動中";
    
    GMSCameraPosition *camera = [GMSCameraPosition cameraWithLatitude:markLat longitude:markLon zoom:12];
    _mapView_.camera = camera;
    self.view = _mapView_;

}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)parseResponse:(NSDictionary *)response {
    NSArray *routes = [response objectForKey:@"routes"];
    
    NSDictionary *route = [routes lastObject];
    if (route) {
        NSString *overviewPolyline = [[route objectForKey: @"overview_polyline"] objectForKey:@"points"];
        _path = [self decodePolyLine:overviewPolyline];
        _steps = [[[route objectForKey:@"legs"]objectAtIndex:0]objectForKey:@"steps"];
        _mileStoneIndexes = [self correspondWith:_path steps:_steps];
        //Polylineを作成
        GMSMutablePath *path = [GMSMutablePath path];
        NSInteger numberOfSteps = _path.count;
        for (NSInteger index = 0; index < numberOfSteps; index++){
            CLLocation *location = [_path objectAtIndex:index];
            CLLocationCoordinate2D coordinate = location.coordinate;
            [path addLatitude:coordinate.latitude longitude:coordinate.longitude];
        }
        
        GMSPolyline *polyline = [GMSPolyline polylineWithPath:path];
        polyline.strokeColor = [UIColor blueColor];
        polyline.strokeWidth = 5.f;
        polyline.map = _mapView_;
        
        // Creates a marker in the center of the map.
        CLLocation *location = _path[0];
        _marker = [[GMSMarker alloc] init];
        _marker.position = CLLocationCoordinate2DMake(location.coordinate.latitude,location.coordinate.longitude);
        _marker.title = @"MyCar";
        _marker.snippet = @"You are Here";
        _marker.icon = [UIImage imageNamed:@"icon-car01.png"];
        _marker.map = _mapView_;
        _mapView_.selectedMarker = _marker;
        
    }
}

-(NSArray*)correspondWith:(NSArray*)pathes steps:(NSArray*)steps{
    float diff = 0.0001;
    NSMutableArray *pathStepIndexArray;
    while(_steps.count!=pathStepIndexArray.count){
        pathStepIndexArray = [NSMutableArray array];
        diff += 0.0001;
        for (int i=0;i<steps.count;i++){
            NSDictionary *step = [steps objectAtIndex:i];
            float stepLat = [[[step objectForKey:@"end_location"] objectForKey:@"lat"] floatValue];
            float stepLon = [[[step objectForKey:@"end_location"] objectForKey:@"lng"] floatValue];
            for(int j=[(NSNumber*)[pathStepIndexArray lastObject] intValue]+1;j<pathes.count;j++){
                CLLocation *path = pathes[j];
                float pathLat = path.coordinate.latitude;
                float pathLon = path.coordinate.longitude;
                    if(pathLat+diff>stepLat&&stepLat>pathLat-diff &&  pathLon+diff>stepLon&&stepLon>pathLon-diff){
                    NSNumber *matchIndex = [[NSNumber alloc]initWithInt:j];
                    [pathStepIndexArray addObject:matchIndex];
                }//pathのlatとstepsのlatは同じではない．理由：描画がずれているのが証拠．
            }
        }
    }
    
    NSLog(@"%@",[pathStepIndexArray description]);
    NSLog(@"%d",pathStepIndexArray.count);
    NSLog(@"%f",diff);
    _coordinate_diff = diff;
    return pathStepIndexArray;
}


-(NSMutableArray *)decodePolyLine:(NSString *)encodedStr {
    NSMutableString *encoded = [[NSMutableString alloc] initWithCapacity:[encodedStr length]];
    [encoded appendString:encodedStr];
    [encoded replaceOccurrencesOfString:@"\\\\" withString:@"\\"
                                options:NSLiteralSearch
                                  range:NSMakeRange(0, [encoded length])];
    NSInteger len = [encoded length];
    NSInteger index = 0;
    NSMutableArray *array = [[NSMutableArray alloc] init];
    NSInteger lat=0;
    NSInteger lng=0;
    while (index < len) {
        NSInteger b;
        NSInteger shift = 0;
        NSInteger result = 0;
        do {
            b = [encoded characterAtIndex:index++] - 63;
            result |= (b & 0x1f) << shift;
            shift += 5;
        } while (b >= 0x20);
        NSInteger dlat = ((result & 1) ? ~(result >> 1) : (result >> 1));
        lat += dlat;
        shift = 0;
        result = 0;
        do {
            b = [encoded characterAtIndex:index++] - 63;
            result |= (b & 0x1f) << shift;
            shift += 5;
        } while (b >= 0x20);
        NSInteger dlng = ((result & 1) ? ~(result >> 1) : (result >> 1));
        lng += dlng;
        NSNumber *latitude = [[NSNumber alloc] initWithFloat:lat * 1e-5];
        NSNumber *longitude = [[NSNumber alloc] initWithFloat:lng * 1e-5];
        
        CLLocation *location = [[CLLocation alloc] initWithLatitude:[latitude floatValue] longitude:[longitude floatValue]];
        [array addObject:location];
    }
    
    return array;
}


@end
