//
//  MWKArticleFetcher.m
//  MediaWikiKit
//
//  Created by Brion on 10/7/14.
//  Copyright (c) 2014 Wikimedia Foundation. All rights reserved.
//

#import "MediaWikiKit.h"

@implementation MWKArticleStore {
    MWKArticle *_article;
    MWKImageList *_imageList;
    NSArray *_sections;
}

-(instancetype)initWithTitle:(MWKTitle *)title dataStore:(MWKDataStore *)dataStore;
{
    self = [self init];
    if (self) {
        if (title == nil) {
            @throw [NSException exceptionWithName:@"MWArticleStoreException"
                                           reason:@"invalid input, title is nil"
                                         userInfo:nil];
        }
        if (dataStore == nil) {
            @throw [NSException exceptionWithName:@"MWArticleStoreException"
                                           reason:@"invalid input, dataStore is nil"
                                         userInfo:nil];
        }
        _title = title;
        _dataStore = dataStore;
        _article = nil;
        _imageList = nil;
        _sections = nil;
    }
    return self;
}

-(MWKArticle *)importMobileViewJSON:(NSDictionary *)dict
{
    NSDictionary *mobileview = dict[@"mobileview"];
    if (!mobileview || ![mobileview isKindOfClass:[NSDictionary class]]) {
        @throw [NSException exceptionWithName:@"MWArticleStoreException"
                                       reason:@"invalid input, not a mobileview api data"
                                     userInfo:nil];
    }

    // Populate article metadata
    _article = [[MWKArticle alloc] initWithTitle:_title dict:mobileview];
    
    // Populate sections
    NSArray *sectionsData = mobileview[@"sections"];
    if (!sectionsData || ![sectionsData isKindOfClass:[NSArray class]]) {
        @throw [NSException exceptionWithName:@"MWArticleStoreException"
                                       reason:@"invalid input, sections missing or not an array"
                                     userInfo:nil];
    }
    NSMutableArray *sections = [NSMutableArray arrayWithCapacity:[sectionsData count]];
    for (NSDictionary *sectionData in sectionsData) {
        MWKSection *section = [[MWKSection alloc] initWithArticle:self.article dict:sectionData];
        [sections addObject:section];
        [self.dataStore saveSection:section];
        if (sectionData[@"text"]) {
            [self.dataStore saveSectionText:sectionData[@"text"] section:section];
        }
    }
    //if (_sections == nil) {
    //    _sections = [NSArray arrayWithArray:sections];
    //}

    [self.dataStore saveArticle:self.article];
    
    return self.article;
}

#pragma mark - getters

-(MWKArticle *)article
{
    if (!_article) {
        _article = [self.dataStore articleWithTitle:self.title];
    }
    return _article;
}

-(NSArray *)sections
{
    if (_sections == nil) {
        NSMutableArray *array = [@[] mutableCopy];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *path = [[self.dataStore pathForTitle:self.title] stringByAppendingPathComponent:@"sections"];
        NSArray *files = [fm contentsOfDirectoryAtPath:path error:nil];
        files = [files sortedArrayUsingComparator:^NSComparisonResult(NSString *obj1, NSString *obj2) {
            int sectionId1 = [obj1 intValue];
            int sectionId2 = [obj2 intValue];
            if (sectionId1 < sectionId2) {
                return NSOrderedAscending;
            } else if (sectionId1 == sectionId2) {
                return NSOrderedSame;
            } else {
                return NSOrderedDescending;
            }
        }];
        NSRegularExpression *redigits = [NSRegularExpression regularExpressionWithPattern:@"^\\d+$" options:0 error:nil];
        for (NSString *subpath in files) {
            NSString *filename = [subpath lastPathComponent];
            NSLog(@"qqq %@", filename);
            NSArray *matches = [redigits matchesInString:filename options:0 range:NSMakeRange(0, [filename length])];
            if (matches && [matches count]) {
                int sectionId = [filename intValue];
                array[sectionId] = [self sectionAtIndex:sectionId];
            }
        }
        _sections = [NSArray arrayWithArray:array];
    }
    return _sections;
}

-(MWKSection *)sectionAtIndex:(NSUInteger)index
{
    if (_sections) {
        return _sections[index];
    } else {
        return [self.dataStore sectionWithId:index article:self.article];
    }
}

-(NSString *)sectionTextAtIndex:(NSUInteger)index
{
    return [self.dataStore sectionTextWithId:index article:self.article];
}

-(MWKImageList *)imageList
{
    if (_imageList == nil) {
        NSString *path = [self.dataStore pathForTitle:self.title];
        NSString *fileName = [path stringByAppendingPathComponent:@"Images.plist"];
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:fileName];
        if (dict) {
            _imageList = [[MWKImageList alloc] initWithTitle:self.title dict:dict];
        } else {
            _imageList = [[MWKImageList alloc] initWithTitle:self.title];
        }
    }
    return _imageList;
}

-(MWKImage *)imageWithURL:(NSString *)url
{
    return [self.dataStore imageWithURL:url title:self.title];
}

-(MWKImage *)largestImageWithURL:(NSString *)url
{
    return [self.dataStore imageWithURL:[self.imageList largestImageVariant:url] title:self.title];
}

-(MWKImage *)importImageURL:(NSString *)url sectionId:(int)sectionId
{
    [self.imageList addImageURL:url sectionId:sectionId];
    MWKImage *image = [[MWKImage alloc] initWithTitle:self.title sourceURL:url];;
    [self.dataStore saveImage:image]; // stub
    return image;
}

-(NSData *)imageDataWithImage:(MWKImage *)image
{
    return [self.dataStore imageDataWithImage:image];
}

-(UIImage *)UIImageWithImage:(MWKImage *)image
{
    NSData *data = [self imageDataWithImage:image];
    if (data) {
        return [UIImage imageWithData:data];
    } else {
        return nil;
    }
}

-(MWKImage *)importImageData:(NSData *)data image:(MWKImage *)image mimeType:(NSString *)mimeType
{
    [self.dataStore saveImageData:data image:image mimeType:mimeType];
    return image;
}

-(void)saveImageList
{
    NSString *path = [self.dataStore pathForTitle:self.title];
    NSString *fileName = [path stringByAppendingPathComponent:@"Images.plist"];
    NSDictionary *dict = [self.imageList dataExport];
    [dict writeToFile:fileName atomically:YES];
}


-(void)setNeedsRefresh:(BOOL)val
{
    NSString *payload = @"needsRefresh";
    NSString *filePath = [self.dataStore pathForArticle:self.article];
    NSString *fileName = [filePath stringByAppendingPathComponent:@"needsRefresh.lock"];
    [payload writeToFile:fileName atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

-(BOOL)needsRefresh
{
    NSString *filePath = [self.dataStore pathForArticle:self.article];
    NSString *fileName = [filePath stringByAppendingPathComponent:@"needsRefresh.lock"];
    return [[NSFileManager defaultManager] fileExistsAtPath:fileName isDirectory:nil];
}

-(void)remove
{
    NSString *path = [self.dataStore pathForArticle:self.article];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

-(MWKImage *)thumbnailImage
{
    NSString *url = [self.imageList imageURLAtIndex:0 sectionId:MWK_SECTIONID_THUMBNAIL];
    if (url == nil) {
        // No recorded thumbnail? See if there's just a first-section image for now.
        url = [self.imageList imageURLAtIndex:0 sectionId:0];
    }
    if (url) {
        return [self imageWithURL:url];
    } else {
        return nil;
    }
}

-(void)setThumbnailImage:(MWKImage *)thumbnailImage
{
    [self.imageList addImageURL:thumbnailImage.sourceURL sectionId:MWK_SECTIONID_THUMBNAIL];
    [self saveImageList];
}

-(UIImage *)thumbnailUIImage
{
    MWKImage *image = self.thumbnailImage;
    if (image) {
        NSData *data = [self imageDataWithImage:image];
        return [UIImage imageWithData:data];
    } else {
        return nil;
    }
}

-(NSArray *)imageURLsForSectionId:(int)sectionId
{
    return [self.imageList imageURLsForSectionId:sectionId];
}

-(NSArray *)imagesForSectionId:(int)sectionId
{
    NSMutableArray *arr = [[NSMutableArray alloc] init];
    for (NSString *url in [self imageURLsForSectionId:sectionId]) {
        [arr addObject:[self imageWithURL:url]];
    }
    return [NSArray arrayWithArray:arr];
}

-(NSArray *)UIImagesForSectionId:(int)sectionId
{
    NSMutableArray *arr = [[NSMutableArray alloc] init];
    for (MWKImage *image in [self imagesForSectionId:sectionId]) {
        [arr addObject:[self UIImageWithImage:image]];
    }
    return [NSArray arrayWithArray:arr];
}


@end
