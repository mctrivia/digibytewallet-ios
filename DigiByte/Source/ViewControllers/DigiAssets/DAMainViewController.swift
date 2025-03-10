//
//  DAOnboardingViewController.swift
//  digibyte
//
//  Created by Yoshi Jaeger on 28.02.19.
//  Copyright © 2019 breadwallet LLC. All rights reserved.
//

import UIKit

class DAMainViewController: UITabBarController {
    // MARK: Public properties
    
    // MARK: Private properties
    private let header = ModalHeaderView(title: "DigiAssets", style: ModalHeaderViewStyle.light)
    private let store: BRStore
    private let wallet: BRWallet
    private let walletManager: WalletManager
    private var tabs: [UIViewController]
    
    private let assetOverview: DAAssetsViewController
    private let assetSend: DASendViewController
    private let assetBurn: DABurnViewController
    
    init(store: BRStore, walletManager: WalletManager, action: AssetMenuAction? = nil) {
        self.store = store
        self.wallet = walletManager.wallet!
        self.walletManager = walletManager
        
        assetOverview = DAAssetsViewController(store: store, wallet: wallet)
        assetSend = DASendViewController(store: store, wallet: wallet, walletManager: walletManager)
        assetBurn = DABurnViewController(store: store, wallet: wallet, walletManager: walletManager)
        
        self.tabs = [
            assetOverview,
            assetSend,
//            DAReceiveViewController(store: store, wallet: wallet),
//            DACreateViewController(),
            assetBurn
        ]
        super.init(nibName: nil, bundle: nil)
        
        addSubviews()
        addConstraints()
        setStyle()
        
        viewControllers = tabs
        tabBar.tintColor = UIColor(red: 38 / 255, green: 152 / 255, blue: 237 / 255, alpha: 1.0) //  38 152 237
        tabBar.barTintColor = UIColor(red: 35 / 255, green: 35 / 255, blue: 60 / 255, alpha: 1.0) //  35 35 60
        tabBar.isTranslucent = false
        
        if #available(iOS 10.0, *) {
            tabBar.unselectedItemTintColor = UIColor(red: 47 / 255, green: 49 / 255, blue: 80 / 255, alpha: 1.0) // 47 49 80
        } else {
            // what will we do below ios10 ?
        }
        
        header.close.tap = { [unowned self] in
            self.dismiss(animated: true, completion: nil)
        }
        
        header.backgroundColor = UIColor.da.backgroundColor.withAlphaComponent(0.7)
        
        actionHandler(action)
    }
    
    func actionHandler(_ action: AssetMenuAction? = nil) {
        switch (action) {
        case .showTx(let assetId, let tx):
            guard let idx = self.tabs.firstIndex(of: assetOverview) else { return }
            self.selectedIndex = idx
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.assetOverview.openDetailView(assetId: assetId)
            }
            break
            
        case .send(let assetId):
            guard let idx = self.tabs.firstIndex(of: assetSend) else { return }
            self.selectedIndex = idx
            assetSend.selectedModel = AssetHelper.getAssetModel(assetID: assetId)
            break
            
        case .burn(let assetId):
            guard let idx = self.tabs.firstIndex(of: assetBurn) else { return }
            assetBurn.selectedModel = AssetHelper.getAssetModel(assetID: assetId)
            self.selectedIndex = idx
            break
            
        default:
            break
        }
    }
    
    private func addSubviews() {
        view.addSubview(header)
    }
    
    private func addConstraints() {
        header.constrain([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 0),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 96)
        ])
    }
    
    private func setStyle() {
        view.backgroundColor = UIColor.da.backgroundColor
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
}
