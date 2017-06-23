//
//  UserProfileModel.swift
//  HiPDA
//
//  Created by leizh007 on 2017/6/23.
//  Copyright © 2017年 HiPDA. All rights reserved.
//

import Foundation

struct UserProfileModel {
    var sections: [ProfileSectionType]
    
    static func createInstance(from html: String) throws -> UserProfileModel {
        let account = try ProfileAccountSection.createInstance(from: html)
        let baseInfos = try html.components(separatedBy: "dashline").map {
            return ProfileSectionType.baseInfo(try ProfileBaseInfoSection.createInstance(from: $0))
        }
        var sections: [ProfileSectionType]
        if account.items.count > 0 && account.items[0].uid != (Settings.shared.activeAccount?.uid ?? 0) {
            sections = [.account(account), .action(try ProfileActionSection.createInstance(from: html))]
            sections.append(contentsOf: baseInfos)
        } else {
            sections = [.account(account)]
            sections.append(contentsOf: baseInfos)
        }
        
        return UserProfileModel(sections: sections)
    }
}
