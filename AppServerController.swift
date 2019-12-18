//
//  AppServerController.swift
//  App
//
//  Created by ocean on 2019/12/17.
//

import Vapor
//import ZIPFoundation
//
/**
 * 将ipa包 xxx_adhoc_1.0_10.ipa -> /Public/publish/
 *
 */

enum IPAType {
    case Adhoc
    case Store
}

class AppServerController: RouteCollection {
    
    func boot(router: Router) throws {
        router.get("list/apps/dev", use: listDevApps)
        router.get("list/apps/release", use: listStoreApps)
    }
}

// MARK: - Routers
extension AppServerController {
    
    func listDevApps(_ req: Request) throws -> Future<View> {
        
        let dir = try req.make(DirectoryConfig.self)
        let publishPath = dir.workDir + "Public/publish"
        
        //1. 归类，将publish目录下的.ipa文件，放入到对应的目录
        // 1.1 解压.ipa文件，获取info.plist文件 =》 get app info
        // 1.2 生成对应的文件目录，将文件mv过去
        // 1.3 删除解压出来的文件和
        let finished = moveIpasIfNeed(publishPath: publishPath)
        if finished {
            print("move ipas finished")
        }
        
        //2. 根据apps_dev目录，生成html，返回
        var host: String?
        req.http.headers.forEach { (name, value) in
            print("name = \(name), value = \(value)")
            if name == "Host" {
                host = value.replacingOccurrences(of: "localhost", with: "10.4.124.200")
            }
        }
        
        let appsPath = publishPath + "/apps_dev"
        guard let appNames = try? FileManager.default.contentsOfDirectory(atPath: appsPath),
                   appNames.count > 0 else {
            return try req.view().render("hello") // no apps
        }
        
        guard let theHost = host else {
            return try req.view().render("hello")
        }
        
        var index = 0
        var appsStr = ""
        for appName in appNames {
            let appPath = appsPath + "/\(appName)"
            guard let versions = try? FileManager.default.contentsOfDirectory(atPath: appPath) else {continue}
            for appVersion in versions {
                let versionPath = appPath + "/\(appVersion)"
                guard let builds = try? FileManager.default.contentsOfDirectory(atPath: versionPath) else {continue}
                for appBuild in builds {
                    let buildPath = versionPath + "/\(appBuild)"
                    guard let ipas = try? FileManager.default.contentsOfDirectory(atPath: buildPath) else {continue}
                    
                    // 是否有manifest file
                    if ipas.count <= 0 {
                        continue
                    }
                    
                    let curtUrl = "https://\(theHost)/publish/apps_dev/\(appName)/\(appVersion)/\(appBuild)"
                    var manifestUrl = ""
                    let manifestName = "manifest.plist"
                    if !ipas.contains(manifestName) {
                       // 生成 manifest file
                        var ipaUrl = ""
                        var bundleId = ""
                        var title = ""
                        for oneIpa in ipas {
                            if oneIpa.hasSuffix(".ipa") {
                                ipaUrl = "\(curtUrl)/\(oneIpa)"
                                title = "\(appName)(\(appVersion)-Dev)"
                                // 解压ipa 获取 bundleId
                                bundleId = unzipForAppInfo(buildPath: buildPath, ipaName: oneIpa, appName: appName)
                            }
                        }
                        
                        if bundleId.count <= 0 {
                            continue
                        }
                        let manifestDic = generalManifestFile(url: ipaUrl, bundleId: bundleId, title: title)
                        
                        let manifestPath = "\(buildPath)/\(manifestName)"
                        guard saveManifestFile(manifestInfo: manifestDic, to: manifestPath) else {
                            continue
                        }
                        manifestUrl = "\(curtUrl)/\(manifestName)"
                    } else {
                        manifestUrl = "\(curtUrl)/\(manifestName)"
                    }
                    
                    if manifestUrl.count <= 0 {
                       continue
                    }
                    
                    let bgColor = (index % 2 == 0) ? "#f1f1f1" : "#e1e1e1"
                    index += 1
                    // <img src="/images/per.png" alt="">
                    var appIconUrl = ""
                    if FileManager.default.fileExists(atPath: "\(buildPath)/appicon.png") {
                        appIconUrl = "\(curtUrl)/appicon.png"
                    }
                    let appIcon = appIconUrl.count > 0 ? appIconUrl : "/images/default_app_icon.png"
                    appsStr = appsStr + """
                        <div class="l-item" style="background:\(bgColor)">
                            <p class="l-name">
                                <img src="\(appIcon)">
                                <span>\(appName)\(appVersion)(\(appBuild))</span>
                            </p>
                            <a class="l-btn" href="itms-services://?action=download-manifest&url=\(manifestUrl)">安装 </a>
                        </div>
                    """
                    
                }
            }
        }
        
        let crtUrl = "https://\(theHost)/server.crt"
        let releasePageUrl = "https://\(theHost)/list/apps/release"
        let leafStr = """
        #set("title") { 应用分发 }
        #set("body") {
        <div style="width:100%;height:60px;background:#e1e1e1;text-align:center;line-height:60px">
            <p font-size: 16px;>内测应用安装 </p>
        </div>
        <div class='a-top'>
            <a href="\(crtUrl)"> 第一次安装，请先安装ssl证书 </a>
            <a href="\(releasePageUrl)"> skip to release </a>
        </div>
        
        <div class="l-box">
            \(appsStr)
            \(appsStr)
        </div>
        }
        #embed("base")
        """
        
        let viewPath = dir.workDir + "Resources/Views"
        try? leafStr.write(toFile: viewPath + "/apps_dev.leaf", atomically: true, encoding: .utf8)
        
        return try req.view().render("apps_dev")
    }
    
    func listStoreApps(_ req: Request) throws -> Future<View> {
        let dir = try req.make(DirectoryConfig.self)
        let publishPath = dir.workDir + "Public/publish"
        
        //1. 归类，将publish目录下的.ipa文件，放入到对应的目录
        // 1.1 解压.ipa文件，获取info.plist文件 =》 get app info
        // 1.2 生成对应的文件目录，将文件mv过去
        // 1.3 删除解压出来的文件和
        let finished = moveIpasIfNeed(publishPath: publishPath)
        if finished {
            print("move ipas finished")
        }
        
        //2. 根据apps_store目录，生成html，返回
        var host: String?
        req.http.headers.forEach { (name, value) in
            print("name = \(name), value = \(value)")
            if name == "Host" {
                host = value.replacingOccurrences(of: "localhost", with: "10.4.124.200")
            }
        }
        
        let appsPath = publishPath + "/apps_store"
        guard let appNames = try? FileManager.default.contentsOfDirectory(atPath: appsPath) else {
            return try req.view().render("hello") // no apps
        }
        
        if appNames.count == 0 {
            return try req.view().render("hello") // no apps
        }
        
        guard let theHost = host else {
            return try req.view().render("hello")
        }
        
        var index = 0
        var appsStr = ""
        for appName in appNames {
            let appPath = appsPath + "/\(appName)"
            guard let versions = try? FileManager.default.contentsOfDirectory(atPath: appPath) else {continue}
            for appVersion in versions {
                let versionPath = appPath + "/\(appVersion)"
                guard let builds = try? FileManager.default.contentsOfDirectory(atPath: versionPath) else {continue}
                for appBuild in builds {
                    let buildPath = versionPath + "/\(appBuild)"
                    guard let ipas = try? FileManager.default.contentsOfDirectory(atPath: buildPath) else {continue}
                    
                    let curtUrl = "https://\(theHost)/publish/apps_store/\(appName)/\(appVersion)/\(appBuild)"
                    
                    if ipas.count > 0 {
                        for oneIpa in ipas {
                            if oneIpa.hasSuffix(".ipa") {
                                var appIconUrl = ""
                                if FileManager.default.fileExists(atPath: "\(buildPath)/appicon.png") {
                                    appIconUrl = "\(curtUrl)/appicon.png"
                                } else {
                                    // 解压ipa 获取 appicon
                                    let _ = unzipForAppInfo(buildPath: buildPath, ipaName: oneIpa, appName: appName)
                                    if FileManager.default.fileExists(atPath: "\(buildPath)/appicon.png") {
                                        appIconUrl = "\(curtUrl)/appicon.png"
                                    }
                                }
                                
                                let ipaUrl = "\(curtUrl)/\(oneIpa)"
                                let appIcon = appIconUrl.count > 0 ? appIconUrl : "/images/default_app_icon.png"
                                let bgColor = (index % 2 == 0) ? "#f1f1f1" : "#e1e1e1"
                                index += 1
                                
                                appsStr = appsStr + """
                                <div class="l-item" style="background:\(bgColor)">
                                    <p class="l-name">
                                        <img src="\(appIcon)">
                                        <span>\(appName)\(appVersion)(\(appBuild))</span>
                                    </p>
                                    <a class="l-btn" href="\(ipaUrl)">下载</a>
                                </div>
                                
                                """
                            }
                        }
                    }
                }
            }
        }
        
        let leafStr = """
        #set("title") { IPA包下载 }
        #set("body") {
            <div style="width:100%;height:60px;background:#e1e1e1;text-align:center;line-height:60px">
                <p font-size: 16px;>IPA包下载，仅用于上传AppStore </p>
            </div>
            \(appsStr)
        \(appsStr)
        \(appsStr)
        }
        #embed("base")
        """
        
        let viewPath = dir.workDir + "Resources/Views"
        try? leafStr.write(toFile: viewPath + "/apps_store.leaf", atomically: true, encoding: .utf8)
        
        return try req.view().render("apps_store")
    }
}

//MARK: - private methods
extension AppServerController {
    
    private func moveIpasIfNeed(publishPath: String) -> Bool {
        guard let paths = try? FileManager.default.contentsOfDirectory(atPath: publishPath) else {return false}
        
        for path in paths {
            if path.hasSuffix(".ipa") {
                let dealed = moveIpaFile(at: path, publishPath: publishPath)
                if dealed {
                    //
                    print("moved file \(path)")
                }
            }
        }
        
        return true
    }
    
    private func fixIpaType(typeStr: String) -> IPAType {
        let appStoreStrs = ["pro", "production", "release", "store", "appstore"]
        if appStoreStrs.contains(typeStr) {
            return .Store
        } else {
            return .Adhoc
        }
    }
    
    private func moveIpaFile(at path: String, publishPath: String) -> Bool {
        if !path.hasSuffix(".ipa") {return false}
        
        let appInfos = path.replacingOccurrences(of: ".ipa", with: "").components(separatedBy: "_")
        if appInfos.count == 4 {
            let appName = appInfos[0]
            let type = appInfos[1]
            let version = appInfos[2]
            let build = appInfos[3]
            
            let ipaType = fixIpaType(typeStr: type)
            if ipaType == .Store {
                let fromPath = "\(publishPath)/\(path)"
                let desDir = "\(publishPath)/apps_store/\(appName)/\(version)/\(build)"
                return moveFile(at: fromPath, toDir: desDir)
            } else if ipaType == .Adhoc {
                //解压，获取bundle id, 生成manifest file? or 获取下载页时生成
                let fromPath = "\(publishPath)/\(path)"
                let desDir = "\(publishPath)/apps_dev/\(appName)/\(version)/\(build)"
                return moveFile(at: fromPath, toDir: desDir)
            }
        }
        return true
    }
    
    private func moveFile(at path: String, toDir: String) -> Bool {
        if !FileManager.default.fileExists(atPath: toDir) {
            do {
                try FileManager.default.createDirectory(atPath: toDir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return false
            }
        }
        
        guard let appName = path.components(separatedBy: "/").last else {
            return false
        }
        
        let toPath = "\(toDir)/\(appName)"
        do {
            try FileManager.default.moveItem(atPath: path, toPath: toPath)
        } catch {
            return false
        }
        
        return true
    }
    
    
    private func generalManifestFile(url: String, bundleId: String, title: String) -> [String: Any] {
        let manifestDic = [
            "items": [
                [
                    "assets": [
                        [
                            "kind": "software-package",
                            "url": url
                        ]
                    ],
                    "metadata": [
                        "bundle-identifier": bundleId,
                        "bundle-version": 1.0,
                        "kind": "software",
                        "releaseNotes": "1.0版本发布",
                        "title": title
                    ]
                ]
            ]
        ]
        return manifestDic
    }
    
    private func saveManifestFile(manifestInfo: [String: Any], to filePath: String) -> Bool {
        guard let outStream = OutputStream(toFileAtPath: filePath, append: false) else {
            return false
        }
        var error: NSError?
        outStream.open()
        let saved = PropertyListSerialization.writePropertyList(manifestInfo, to: outStream, format: .xml, options: 0, error: &error)
        outStream.close()
        return saved > 0
    }
    
    /**
     * @param buildPath xxx/Public/publish/apps_dev/appName/1.0/1
     * @param ipaName xxx_dev_1.0_1.ipa
     * @param appName xxx
     * @return bundleId
     */
    // 返回bundleId & 获取app图标
    private func unzipForAppInfo(buildPath: String, ipaName: String, appName: String) -> String {
        let ipaPath = "\(buildPath)/\(ipaName)"
        let ipaFileUrl = URL(fileURLWithPath: ipaPath)
        let toFileUrl = URL(fileURLWithPath: buildPath, isDirectory: true)
        
        var bundleId = ""
        do {
            // 移除解压文件夹
            let unzipDir = "\(buildPath)/Payload"
            if FileManager.default.fileExists(atPath: unzipDir) {
                try FileManager.default.removeItem(atPath: unzipDir)
            }
            
            try FileManager.default.unzipItem(at: ipaFileUrl, to: toFileUrl)
            let payloadPath = "\(buildPath)/Payload"
            var excuteName = "\(appName).app"
            do {
                let items = try FileManager.default.contentsOfDirectory(atPath: payloadPath)
                for item in items {
                    if item.hasSuffix(".app") {
                        excuteName = item
                    }
                }
            } catch {
                print("get excute name failed")
            }
            
            let infoPath = "\(buildPath)/Payload/\(excuteName)/info.plist"
            
            let infoData = try Data(contentsOf: URL(fileURLWithPath: infoPath), options: .alwaysMapped)
            if let infoDic = try PropertyListSerialization.propertyList(from: infoData, options: .mutableContainers, format: .none) as? [String: Any],
                let bundId = infoDic["CFBundleIdentifier"] as? String {
                bundleId = bundId
            }
            
            // find appicon & save appicon
            let bundlePath = "\(buildPath)/Payload/\(excuteName)"
            do {
                let items = try FileManager.default.contentsOfDirectory(atPath: bundlePath)
                var appIcon = ""
                for item in items {
                    if item.hasSuffix(".png") && item.hasPrefix("AppIcon") {
                        appIcon = item
                    }
                }
                
                // move app icon
                if appIcon.count > 0 {
                    let fromPath = "\(bundlePath)/\(appIcon)"
                    let toPath = "\(buildPath)/appicon.png"
                    do {
                        try FileManager.default.moveItem(atPath: fromPath, toPath: toPath)
                    } catch {
                        print("move app icon failed")
                    }
                }
            } catch {
                print("get app icon failed")
            }
            
            // 移除解压文件夹
            try FileManager.default.removeItem(atPath: unzipDir)
        } catch {
            print("unzip error")
        }
        return bundleId
    }
    
}


