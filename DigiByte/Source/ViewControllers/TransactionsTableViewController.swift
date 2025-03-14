//
//  TransactionsTableViewController.swift
//  breadwallet
//
//  Created by Adrian Corscadden on 2016-11-16.
//  Copyright © 2016 breadwallet LLC. All rights reserved.
//

import UIKit

private let promptDelay: TimeInterval = 0.6

enum TransactionFilterMode {
    case showAll
    case showOutgoing
    case showIncoming
}

// global
// only show table row animation once!
var hideRows: Bool = true
var firstLogin: Bool = true

class TransactionsTableViewController : UITableViewController, Subscriber, Trackable {

    //MARK: - Public
    init(store: BRStore, didSelectTransaction: @escaping ([Transaction], Int) -> Void, didSelectAssetTx: @escaping (Transaction) -> Void, kvStore: BRReplicatedKVStore? = nil, filterMode: TransactionFilterMode = .showAll) {
        self.store = store
        self.kvStore = kvStore
        self.didSelectTransaction = didSelectTransaction
        self.didSelectAssetTx = didSelectAssetTx
        self.isBtcSwapped = store.state.isBtcSwapped
        self.filterMode = filterMode
        super.init(nibName: nil, bundle: nil)
    }

    let filterMode: TransactionFilterMode
    let didSelectTransaction: ([Transaction], Int) -> Void
    let didSelectAssetTx: (Transaction) -> Void
    
    var filters: [TransactionFilter] = [] {
        didSet {
            transactions = filters.reduce(allTransactions, { $0.filter($1) })
            tableView.reloadData()
        }
    }
    
    var kvStore: BRReplicatedKVStore? {
        didSet {
            tableView.reloadData()
        }
    }

    var walletManager: WalletManager?

    //MARK: - Private
    private let store: BRStore
    private let headerCellIdentifier = "HeaderCellIdentifier"
    private let transactionCellIdentifier = "TransactionCellIdentifier"
    private var transactions: [Transaction] = []
    private var allTransactions: [Transaction] = [] {
        didSet {
            switch filterMode {
            case .showAll:
                transactions = allTransactions
            case .showIncoming:
                transactions = allTransactions.filter({ (t) -> Bool in
                    t.direction == .received
                })
            case .showOutgoing:
                transactions = allTransactions.filter({ (t) -> Bool in
                    t.direction == .sent
                })
            }
            
        }
    }
    private var isBtcSwapped: Bool {
        didSet {
            reload()
        }
    }
    private var rate: Rate? {
        didSet {
            reload()
        }
    }
    private let emptyMessage = UILabel.wrapping(font: .customBody(size: 16.0), color: .grayTextTint)
    private var currentPrompt: Prompt? {
        didSet {
            if currentPrompt != nil && oldValue == nil {
                tableView.beginUpdates()
                tableView.insertSections(IndexSet(integer: 0), with: .automatic)
                tableView.endUpdates()
            } else if currentPrompt == nil && oldValue != nil {
                tableView.beginUpdates()
                tableView.deleteSections(IndexSet(integer: 0), with: .automatic)
                tableView.endUpdates()
            }
        }
    }
    private var hasExtraSection: Bool {
        return (currentPrompt != nil)
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // this will only be called once after login (create a fancy animation)
        cell.clipsToBounds = true
        
        if firstLogin {
            cell.transform = CGAffineTransform(translationX: 0, y: 800)
            UIView.spring(0.5 + (Double(indexPath.row) * 0.2), animations: {
                cell.transform = CGAffineTransform.identity
            }) { (completed) in
                firstLogin = false
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(TransactionCardViewCell.self, forCellReuseIdentifier: transactionCellIdentifier)
        tableView.register(TransactionCardViewCell.self, forCellReuseIdentifier: headerCellIdentifier)
        tableView.separatorStyle = .none
        tableView.estimatedRowHeight = 100.0
        tableView.rowHeight = UITableView.automaticDimension
        tableView.backgroundColor = UIColor(red: 0x19 / 255, green: 0x1b / 255, blue: 0x2a / 255, alpha: 1)
        
        // subscriptions
        store.subscribe(self, selector: { $0.walletState.transactions != $1.walletState.transactions },
                        callback: { state in
                            self.allTransactions = state.walletState.transactions
                            DispatchQueue.main.async {
                                self.reload()
                            }
        })
        
        store.subscribe(self, selector: { $0.isLoginRequired != $1.isLoginRequired },
            callback: { state in
                guard !state.isLoginRequired else { return }
                hideRows = false
                self.tableView.reloadData()
        })

        // create animation
        store.subscribe(self, selector: { $0.walletState.syncState != $1.walletState.syncState || $0.isLoginRequired != $1.isLoginRequired },
                        callback: { state in
                            if !state.isLoginRequired && state.walletState.syncState == .success {
                                DispatchQueue.main.asyncAfter(deadline: .now(), execute: {
                                    hideRows = false
                                })
                            }
        })
        
        store.subscribe(self,
                        selector: { $0.isBtcSwapped != $1.isBtcSwapped },
                        callback: { self.isBtcSwapped = $0.isBtcSwapped })
        store.subscribe(self,
                        selector: { $0.currentRate != $1.currentRate},
                        callback: { self.rate = $0.currentRate })
        store.subscribe(self, selector: { $0.maxDigits != $1.maxDigits }, callback: {_ in 
            self.reload()
        })

        store.subscribe(self, selector: { $0.recommendRescan != $1.recommendRescan }, callback: { _ in
            self.attemptShowPrompt()
        })
        store.subscribe(self, selector: { $0.walletState.syncState != $1.walletState.syncState }, callback: { _ in
            self.reload()
        })
        store.subscribe(self, name: .didUpgradePin, callback: { _ in
            if self.currentPrompt?.type == .upgradePin {
                self.currentPrompt = nil
            }
        })
        store.subscribe(self, name: .didEnableShareData, callback: { _ in
            if self.currentPrompt?.type == .shareData {
                self.currentPrompt = nil
            }
        })
        store.subscribe(self, name: .didWritePaperKey, callback: { _ in
            if self.currentPrompt?.type == .paperKey {
                self.currentPrompt = nil
            }
        })

        store.subscribe(self, name: .txMemoUpdated(""), callback: {
            guard let trigger = $0 else { return }
            if case .txMemoUpdated(let txHash) = trigger {
                self.reload(txHash: txHash)
            }
        })

        emptyMessage.textAlignment = .center
        emptyMessage.text = S.TransactionDetails.emptyMessage
        reload()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    private func reload(txHash: String) {
        self.transactions.enumerated().forEach { i, tx in
            if tx.hash == txHash {
                DispatchQueue.main.async {
                    self.tableView.beginUpdates()
                    self.tableView.reloadRows(at: [IndexPath(row: i, section: self.hasExtraSection ? 1 : 0)], with: .automatic)
                    self.tableView.endUpdates()
                }
            }
        }
    }

    // MARK: - Table view data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        return hasExtraSection ? 2 : 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if hasExtraSection && section == 0 {
            return 1
        } else {
            return hideRows ? 0 : transactions.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if hasExtraSection && indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: headerCellIdentifier, for: indexPath)
            if let transactionCell = cell as? TransactionCardViewCell {
                transactionCell.setStyle(.single)
                transactionCell.container.subviews.forEach {
                    $0.removeFromSuperview()
                }
                if let prompt = currentPrompt {
                    transactionCell.container.addSubview(prompt)
                    prompt.constrain(toSuperviewEdges: nil)
                    prompt.constrain([
                        prompt.heightAnchor.constraint(equalToConstant: 88.0) ])
                    transactionCell.selectionStyle = .default
                }
            }
            return cell
        } else {
            let numRows = tableView.numberOfRows(inSection: indexPath.section)
            var style: TransactionCellStyle = .middle
            if numRows == 1 {
                style = .single
            }
            if numRows > 1 {
                if indexPath.row == 0 {
                    style = .first
                }
                if indexPath.row == numRows - 1 {
                    style = .last
                }
            }

            let cell = tableView.dequeueReusableCell(withIdentifier: transactionCellIdentifier, for: indexPath)
            if let transactionCell = cell as? TransactionCardViewCell, let rate = rate {
                transactionCell.setStyle(style)
                transactions[indexPath.row].kvStore = kvStore
                transactionCell.setTransaction(transactions[indexPath.row], isBtcSwapped: isBtcSwapped, rate: rate, maxDigits: store.state.maxDigits, isSyncing: store.state.walletState.syncState != .success)
                transactionCell.layer.zPosition = CGFloat(indexPath.row)
            }
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if hasExtraSection && section == 1 {
            return UIView(color: .clear)
        } else {
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let tx = transactions[indexPath.row]
        
        if tx.isAssetTx {
            didSelectAssetTx(tx)
        } else {
            didSelectTransaction(transactions, indexPath.row)
        }
    }

    private func reload() {
        self.tableView.reloadData()
        
        if transactions.count == 0 {
            if emptyMessage.superview == nil {
                tableView.addSubview(emptyMessage)
                emptyMessage.constrain([
                    emptyMessage.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
                    emptyMessage.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -accountHeaderHeight),
                    emptyMessage.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -C.padding[2]) ])
            }
        } else {
            emptyMessage.removeFromSuperview()
        }
    }

    private func attemptShowPrompt() {
        guard let walletManager = walletManager else { return }
        let types = PromptType.defaultOrder
        if let type = types.first(where: { $0.shouldPrompt(walletManager: walletManager, state: store.state) }) {
            //self.saveEvent("prompt.\(type.name).displayed")
            currentPrompt = Prompt(type: type)
            currentPrompt?.close.tap = { [weak self] in
                //self?.saveEvent("prompt.\(type.name).dismissed")
                self?.currentPrompt = nil
            }
            if type == .biometrics {
                UserDefaults.hasPromptedBiometrics = true
            }
            if type == .shareData {
                UserDefaults.hasPromptedShareData = true
            }
        } else {
            currentPrompt = nil
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
