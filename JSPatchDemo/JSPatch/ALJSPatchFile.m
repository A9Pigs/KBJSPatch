//
//  ALJSPatchFile.m
//  JSPatchDemo
//
//  Created by aoliday on 16/5/19.
//  Copyright © 2016年 aoliday. All rights reserved.
//

#import "ALJSPatchFile.h"
#import "ALJSPatchDownloadFile.h"
#import "RSAEncryptor.h"
#import "ALFileManager.h"
#import "NSString+ALMD5.h"
#import <JSPatch/JPEngine.h>
#import "NSString+ALMD5.h"

FOUNDATION_EXTERN NSString * ALJSPatchExecuteMinVersion(void);
FOUNDATION_EXTERN NSString * ALJSPatchExecuteMaxVersion(void);
FOUNDATION_EXTERN NSInteger valueWithString(NSString *str);

#define JSPATCH_COMPONENT @"JSPatch" //JSPatch文件目录Key.
#define BUG_DOWNLOAD_TIME @"fixbugDownloadDate" //fixBug.js的下载时间.
#define VERSION_DOWNLOAD_TIME @"versionDownloadDate"//version.js的下载时间.
#define BUG_MODIFY_TIME @"fixbugModifyDate"//fixBug.js的修改时间. 修改者上传fixBug.js的时间.
#define JSPATCH_CRASH_FLAG @"JSPatch_Handing_crash_flag" //执行JSPatch过程中产生崩溃的标记位
/*
 *执行RSA的密码,此处已被修改,请参照链接
 *http://www.cnblogs.com/makemelike/articles/3802518.html
 *按照教程自己生成公钥私钥和密码.
 */
#define RSA_PASSWORD @"aoliday"
#define RSA_HANDING_STEP_LENGTH 50 //由于明文太长会导致RSA无法加解密,所以对JS文件进行分段加解密,此为每段步长.
#define RSA_HANDING_SEPERATE @"(_RSA_HANDING_SEPERATE_)" //RSA分段加解密的分隔符.
#define JSPATCH_FIX_BUG_VERSION [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleShortVersionString"]
//#define JSPATCH_FIX_BUG_VERSION @"2.2.1" //制定到某一个版本进行该版本的bug修复.
#define JSPATCH_TEST_MODEL 0 //1为测试模式 线上的请更改为0.

@implementation ALJSPatchFile

NSString * ALJSPatchExecuteMinVersion(void) {
    
    return [ALJSPatchFile minVersion];
}

NSString * ALJSPatchExecuteMaxVersion(void) {
    
    return [ALJSPatchFile maxVersion];
}

NSInteger IntegerValueWithString(NSString *str) {
    
    NSInteger value = 0;
    str = [str stringByReplacingOccurrencesOfString:@"." withString:@""];
    value = [str integerValue];
    return value;
}

//默认是不执行.所以最低版本和最高版本都是0.;
+ (NSString *)maxVersion {return @"0";}
+ (NSString *)minVersion {return @"0";}
+ (NSString *)fixBugModifyTime {return @"0";}
+ (NSString *)encryptMD5String {return @"0";}

+ (void)executeJSPatch {
    
    [self modifyVersionTimeInterval];
    
    BOOL testModel = JSPATCH_TEST_MODEL;
    
    if (testModel) {
        
        [self doTestJS];
        return;
    }
        
    [self beginExecuteJSPatch:YES];
    //当前版本号.
    NSInteger currentVersion = IntegerValueWithString(JSPATCH_FIX_BUG_VERSION);
    //获取plist文件的目录.
    __block NSString *plistPath = [[ALFileManager cacheWithComponent:JSPATCH_COMPONENT] stringByAppendingPathComponent:@"record.plist"];
    
    __block NSMutableDictionary *modifyData = [[NSDictionary dictionaryWithContentsOfFile:plistPath] mutableCopy];
    
    if (!modifyData) {
        
        if ([ALFileManager createFileAtPath:plistPath] == ALCreateFileSuccessed) {
            
            modifyData = [[NSDictionary dictionary] mutableCopy];
        }
    }
    
    //执行version.js.
    [ALJSPatchFile executeJSPatchWithPath:[cachePath() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@/version.js",JSPATCH_COMPONENT]] fixBugJS:NO];
    //获取最新的bug.js的修改时间.
    NSString *bugModifyTime = [ALJSPatchFile fixBugModifyTime];
    @synchronized([self class]) {
        //存储最新的fixbug.js的修改时间.
        [modifyData setObject:[NSString stringWithFormat:@"%ld",bugModifyTime.integerValue] forKey:BUG_MODIFY_TIME];
        [modifyData writeToFile:plistPath atomically:NO];
    }
    //下载最新的version.js文件.
    //这里使用的七牛的公有https免费仓库,请去七牛上配置自己的下载地址.
    [ALJSPatchDownloadFile downloadUrl:[NSURL URLWithString:@"https://dn-anine.qbox.me/version.js"]
                     cacheURLComponent:JSPATCH_COMPONENT
                       completionBlock:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
                           
                           if (error) {
                               
                               NSLog(@"downLoadFileError:%@",error.description);
                               [ALFileManager removePath:[filePath path]];
                           }else {
                               @synchronized([self class]) {
                                   //下载完成,存储fixBug.js的下载时间.
                                   [modifyData setObject:[NSString stringWithFormat:@"%ld",(NSInteger)([NSDate timeIntervalSinceReferenceDate])] forKey:VERSION_DOWNLOAD_TIME];
                                   [modifyData writeToFile:plistPath atomically:YES];
                               }
                           }
                           /*
                            *这里可能存在一个bug,异步线程下载version.js可能会比bug.js慢.
                            *这种情况下,执行JSPatch并没有真正的结束,处理的成本较高且可能无意义,暂不处理此情况.
                            */
                           [self beginExecuteJSPatch:NO];
                       }];
    
    void (^downloadBugJSBlock) (void) = ^(void) {
        //这里使用的七牛的公有https免费仓库,请去七牛上配置自己的下载地址.
        [ALJSPatchDownloadFile downloadUrl:[NSURL URLWithString:@"https://dn-anine.qbox.me/fixBug.js"]
                         cacheURLComponent:JSPATCH_COMPONENT
                           completionBlock:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
                               
                               if (error) {
                                   
                                   NSLog(@"downLoadFileError:%@",error.description);
                                   [ALFileManager removePath:filePath.absoluteString];
                               }else {
                                   @synchronized([self class]) {
                                       //下载完成,存储fixBug.js的下载时间.
                                       [modifyData setObject:[NSString stringWithFormat:@"%ld",(NSInteger)([NSDate timeIntervalSinceReferenceDate])] forKey:BUG_DOWNLOAD_TIME];
                                       [modifyData writeToFile:plistPath atomically:YES];
                                   }
                               }
                               /*
                                *这里可能存在一个bug,异步线程下载version.js可能会比bug.js慢.
                                *这种情况下,执行JSPatch并没有真正的结束,处理的成本较高且可能无意义,暂不处理此情况.
                                */
                               [self beginExecuteJSPatch:NO];
                           }];
    };
    
    /*
     * 如果不存在fixBug.js文件则直接进入下载,
     * 用户在第二次使用时就可以正常使用fixBug.js功能.
     */
    if (![[NSFileManager defaultManager] fileExistsAtPath:[cachePath() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@/fixBug.js",JSPATCH_COMPONENT]]]) {
        
        downloadBugJSBlock();
        
    }else {
        
        NSInteger minVersion = IntegerValueWithString(ALJSPatchExecuteMinVersion());
        NSInteger maxVersion = IntegerValueWithString(ALJSPatchExecuteMaxVersion());
        //如果当前App的版本 在fixBug.js制定的版本范围之内,则继续执行...
        if (currentVersion >= minVersion && currentVersion <= maxVersion) {
            //首先执行fixBug.js文件
            [ALJSPatchFile executeJSPatchWithPath:[cachePath() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@/fixBug.js",JSPATCH_COMPONENT]] fixBugJS:YES];
            //走到这说明,fixBug.js文件执行成功,这里是检测是否需要去更新fixBug.js文件.
            NSTimeInterval bugDownloadTime = [modifyData[BUG_DOWNLOAD_TIME] integerValue];
            NSTimeInterval bugModifyTime = [modifyData[BUG_MODIFY_TIME] integerValue];
            
            //如果 js文件的下载时间 小于 js文件的修改时间....说明 js文件已经被更新,应该下载.
            if (bugDownloadTime <= bugModifyTime) {
                //进入下载.
                downloadBugJSBlock();
                
            }else {
                
                [self beginExecuteJSPatch:NO];
            }
        }else {
            
            [self beginExecuteJSPatch:NO];
        }
    }
}

+ (BOOL)executeJSPatchWithPath:(NSString *)path fixBugJS:(BOOL)isFixBugJS {
    
    [JPEngine startEngine];
    
    BOOL fileExist = NO;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        
        fileExist = YES;
        
        NSString *script = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        
        //如果是bug.js脚本,首先比对md5值,如果加密脚本的md5值跟服务器下发的md5一致,则说明该脚本是安全脚本.
        if (isFixBugJS && [[self encryptMD5String] isEqualToString:[NSString md5HexDigest:script]]) {
            //如果对较不成功,则不执行该脚本.
            return fileExist;
        }
        
        NSArray *decrys = [script componentsSeparatedByString:RSA_HANDING_SEPERATE];
        NSString *decrypt = @"";
        for (NSString *decry in decrys) {
            
            if (decry && [decry isKindOfClass:[NSString class]] && decry.length) {
                
                decrypt = [decrypt stringByAppendingString:[ALJSPatchFile decrypt:decry]];
            }
        }
        
        if (decrypt && [decrypt isKindOfClass:[NSString class]]) {
            
            //使用try catch可以保证执行script的过程中不crash.
            @try {
                //执行响应版本的脚本.
                if (isFixBugJS) {
                    
                    [JPEngine evaluateScript:[ALJSPatchFile parseScript:decrypt fromVersion:JSPATCH_FIX_BUG_VERSION]];
                }else {
                    
                    [JPEngine evaluateScript:decrypt];
                }
            }
            @catch (NSException *exception) {
                NSLog(@"crash   evalute Script");
            }
            @finally {
                
            }
        }
    }
    
    return fileExist;
}

+ (void)modifyVersionTimeInterval {
    
    NSLog(@"JSPatch最新时间: %lf",[NSDate timeIntervalSinceReferenceDate]);
}

/*
 *JSPatch的容错处理.
 * 规则:
 *  执行JSPatch方法开始,将标志位置为1.
 *  执行JSPatch方法结束,将标志位置为0.
 *  下一次读取,如果发现标志位不为1,则说明在执行过程中发生了程序异常,标志位++.
 *  如果读到标志位为5,这说明执行JSPatch程序过程中已经发生了五次crash,此时清理掉整个JSPatch文件目录.
 */
+ (void)beginExecuteJSPatch:(BOOL)begin {
    
    NSString *plistPath = [[ALFileManager cacheWithComponent:JSPATCH_COMPONENT] stringByAppendingPathComponent:@"record.plist"];
    NSMutableDictionary *modifyData = [[NSDictionary dictionaryWithContentsOfFile:plistPath] mutableCopy];
    if (!modifyData) {
        
        if ([ALFileManager createFileAtPath:plistPath] == ALCreateFileSuccessed) {
            
            modifyData = [[NSDictionary dictionary] mutableCopy];
        }
    }
    
    NSInteger crashTime = [modifyData[JSPATCH_CRASH_FLAG] integerValue];
    if (begin) {
        
        if (crashTime > 0) {
            
            //清理掉JSPatch文件.
            [ALFileManager removePath:[cachePath() stringByAppendingPathComponent:JSPATCH_COMPONENT]];
        }else {
            
            crashTime ++;
        }
    }else {
        
        crashTime = 0;
    }
    [modifyData setObject:@(crashTime) forKey:JSPATCH_CRASH_FLAG];
    [modifyData writeToFile:plistPath atomically:YES];
}


+ (void)doTestJS {
    
    [JPEngine startEngine];
    //执行bug.js
    NSString *bugPath = [[NSBundle mainBundle] pathForResource:@"fixBug" ofType:@"js"];
    NSString *bugScript = [NSString stringWithContentsOfFile:bugPath encoding:NSUTF8StringEncoding error:nil];
    [JPEngine evaluateScript:[ALJSPatchFile parseScript:bugScript fromVersion:JSPATCH_FIX_BUG_VERSION]];
    //执行version.js
    NSString *versionPath = [[NSBundle mainBundle] pathForResource:@"version" ofType:@"js"];
    NSString *versionScript = [NSString stringWithContentsOfFile:versionPath encoding:NSUTF8StringEncoding error:nil];
    [JPEngine evaluateScript:versionScript];
    
    
    
    //将fixBug.js文件加密.
    NSString *bugEncryString = [ALJSPatchFile handleEncryScript:bugScript name:@"fixBug.js"];
    
    //获取bug.js加密后的md5值.
    NSString *bugEncryMD5String = [NSString md5HexDigest:bugEncryString];
    
    //获取当前时间.
    NSTimeInterval currentInterval = [NSDate timeIntervalSinceReferenceDate];
    
    //重新拼凑version.js. 修改bugModifyTime的值,添加md5值.
    versionScript = [[versionScript componentsSeparatedByString:@"_$_SEPERATE_LINE_$_"] firstObject];
    NSString *appendString = [NSString stringWithFormat:@"\
                                                        fixBugModifyTime : function() {\
                                                            \
                                                            return '%@';\
                                                        },\
                                                          encryptMD5String : function() {\
                                                            return '%@';\
                                                        }\
                                                    });",[NSString stringWithFormat:@"%f",currentInterval],bugEncryMD5String];
    versionScript = [versionScript stringByAppendingString:appendString];
    //将重组的version.js加密
    [ALJSPatchFile handleEncryScript:versionScript name:@"version.js"];
}

//将指定文件加密.
+ (NSString *)handleEncryScript:(NSString *)bugScript name:(NSString *)name {
    
    NSString *encryString = [self segeEncryptScript:bugScript];
    
    NSString *encryptFilePath = [[ALFileManager cacheWithComponent:JSPATCH_COMPONENT] stringByAppendingPathComponent:name];
    if ([encryString writeToFile:encryptFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
        
        NSLog(@"%@加密文件已保存至:%@",name,encryptFilePath);
        [self segeParseEncryptStringWithPath:encryptFilePath];
    }
    
    return encryString;
}

//分段加密制定字符串.
+ (NSString *)segeEncryptScript:(NSString *)script {
    
    NSInteger index = 0;
    NSString *encryString =@"";
    while (index <= script.length) {
        
        NSInteger step = RSA_HANDING_STEP_LENGTH;
        if(script.length - index <= RSA_HANDING_STEP_LENGTH) {
            
            step = script.length - index;
        }
        
        if (step == 0) {
            
            break;
        }
        NSString *tempStr = [script substringWithRange:NSMakeRange(index, step)];
        tempStr = [ALJSPatchFile encrypt:tempStr];
        encryString = [encryString stringByAppendingString:[NSString stringWithFormat:@"%@%@",RSA_HANDING_SEPERATE,tempStr]];
        
        index += step;
    }
    
    return encryString;
}

//解析指定路径下的分段加密字符串.
+ (NSString *)segeParseEncryptStringWithPath:(NSString *)encryptFilePath {
    
        NSString *decrypt = @"";
        NSString *encryString = [NSString stringWithContentsOfFile:encryptFilePath encoding:NSUTF8StringEncoding error:nil];
        if (encryString) {
            
            NSArray *decrys = [encryString componentsSeparatedByString:RSA_HANDING_SEPERATE];

            for (NSString *decry in decrys) {
                
                if (decry && [decry isKindOfClass:[NSString class]] && decry.length) {
                    
                    decrypt = [decrypt stringByAppendingString:[ALJSPatchFile decrypt:decry]];
                }
            }
            NSLog(@"解出来的结果是：%@",decrypt);
        }
    return decrypt;
}

//获取某个版本的脚本信息.
+ (NSString *)parseScript:(NSString *)script fromVersion:(NSString *)version {
    
    NSArray *scripts = [script componentsSeparatedByString:@"VERSION_SEPERATE_"];
    NSString *resultScript = @"";
    for (NSString *subScript in scripts) {
        
        if ([subScript hasPrefix:version]) {
            
            resultScript = [[subScript componentsSeparatedByString:version] lastObject];
        }
    }
    return resultScript;
}

/*
 *RSA加密
 */
+ (NSString *)encrypt:(NSString *)string {
    
    RSAEncryptor* rsaEncryptor = [[RSAEncryptor alloc] init];
    NSString* publicKeyPath = [[NSBundle mainBundle] pathForResource:@"public_key" ofType:@"der"];
    NSString* privateKeyPath = [[NSBundle mainBundle] pathForResource:@"private_key" ofType:@"p12"];
    [rsaEncryptor loadPublicKeyFromFile: publicKeyPath];
    [rsaEncryptor loadPrivateKeyFromFile: privateKeyPath password:RSA_PASSWORD];
    
    NSString* restrinBASE64STRING = [rsaEncryptor rsaEncryptString:string];
    //    NSLog(@"Encrypted: %@", restrinBASE64STRING);
    return restrinBASE64STRING;
}

/*
 *RSA解密
 */
+ (NSString *)decrypt:(NSString *)string {
    
    RSAEncryptor* rsaEncryptor = [[RSAEncryptor alloc] init];
    NSString* publicKeyPath = [[NSBundle mainBundle] pathForResource:@"public_key" ofType:@"der"];
    NSString* privateKeyPath = [[NSBundle mainBundle] pathForResource:@"private_key" ofType:@"p12"];
    [rsaEncryptor loadPublicKeyFromFile: publicKeyPath];
    [rsaEncryptor loadPrivateKeyFromFile: privateKeyPath password:RSA_PASSWORD];
    
    NSString * restrinBASE64STRING=[rsaEncryptor rsaDecryptString:string];
    //    NSLog(@"Decrypted: %@", restrinBASE64STRING);
    return restrinBASE64STRING;
}

@end
