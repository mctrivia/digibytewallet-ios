//
//  FeeUpdater.swift
//  breadwallet
//
//  Created by Adrian Corscadden on 2017-03-02.
//  Copyright © 2017 breadwallet LLC. All rights reserved.
//

import Foundation

struct Fees {
    let regular: UInt64
    let economy: UInt64
}

extension Fees {
    static var defaultFees: Fees {
        return Fees(regular: defaultFeePerKB, economy: defaultFeePerKB)
    }
}

// regular fee amount
private let defaultFeePerKB: UInt64 = 50000

class FeeUpdater : Trackable {

    //MARK: - Public
    init(walletManager: WalletManager, store: BRStore) {
        self.walletManager = walletManager
        self.store = store
    }

    func refresh(completion: @escaping () -> Void) {
        walletManager.apiClient?.feePerKb { newFees, error in
            guard error == nil else { print("feePerKb error: \(String(describing: error))"); completion(); return }
            guard newFees.regular < self.maxFeePerKB && newFees.economy > self.minFeePerKB else {
                //self.saveEvent("wallet.didUseDefaultFeePerKB")
                return
            }
            self.store.perform(action: UpdateFees.set(newFees))
            completion()
        }

        if timer == nil {
            timer = Timer.scheduledTimer(timeInterval: feeUpdateInterval, target: self, selector: #selector(intervalRefresh), userInfo: nil, repeats: true)
        }
    }

    func refresh() {
        refresh(completion: {})
    }

    @objc func intervalRefresh() {
        refresh(completion: {})
    }

    //MARK: - Private
    private let walletManager: WalletManager
    private let store: BRStore
    private let feeKey = "FEE_PER_KB"
    private let txFeePerKb: UInt64 = 1000
    private lazy var minFeePerKB: UInt64 = {
        return ((self.txFeePerKb*1000 + 190)/191) // minimum relay fee on a 191byte tx
    }()
    private let maxFeePerKB: UInt64 = 10000000
    private var timer: Timer?
    private let feeUpdateInterval: TimeInterval = 15

}
