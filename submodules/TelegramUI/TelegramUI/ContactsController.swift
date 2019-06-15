import Foundation
import UIKit
import Display
import AsyncDisplayKit
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import DeviceAccess

private func fixListNodeScrolling(_ listNode: ListView, searchNode: NavigationBarSearchContentNode) -> Bool {
    if searchNode.expansionProgress > 0.0 && searchNode.expansionProgress < 1.0 {
        let scrollToItem: ListViewScrollToItem
        let targetProgress: CGFloat
        if searchNode.expansionProgress < 0.6 {
            scrollToItem = ListViewScrollToItem(index: 1, position: .top(-navigationBarSearchContentHeight), animated: true, curve: .Default(duration: nil), directionHint: .Up)
            targetProgress = 0.0
        } else {
            scrollToItem = ListViewScrollToItem(index: 1, position: .top(0.0), animated: true, curve: .Default(duration: nil), directionHint: .Up)
            targetProgress = 1.0
        }
        searchNode.updateExpansionProgress(targetProgress, animated: true)
        
        listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: ListViewDeleteAndInsertOptions(), scrollToItem: scrollToItem, updateSizeAndInsets: nil, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
        return true
    } else if searchNode.expansionProgress == 1.0 {
        var sortItemNode: ListViewItemNode?
        var nextItemNode: ListViewItemNode?
        
        listNode.forEachItemNode({ itemNode in
            if sortItemNode == nil, let itemNode = itemNode as? ContactListActionItemNode {
                sortItemNode = itemNode
            } else if sortItemNode != nil && nextItemNode == nil {
                nextItemNode = itemNode as? ListViewItemNode
            }
        })
        
        if let sortItemNode = sortItemNode {
            let itemFrame = sortItemNode.apparentFrame
            if itemFrame.contains(CGPoint(x: 0.0, y: listNode.insets.top)) {
                var scrollToItem: ListViewScrollToItem?
                if itemFrame.minY + itemFrame.height * 0.6 < listNode.insets.top {
                    scrollToItem = ListViewScrollToItem(index: 0, position: .top(-50), animated: true, curve: .Default(duration: nil), directionHint: .Up)
                } else {
                    scrollToItem = ListViewScrollToItem(index: 0, position: .top(0), animated: true, curve: .Default(duration: nil), directionHint: .Up)
                }
                listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: ListViewDeleteAndInsertOptions(), scrollToItem: scrollToItem, updateSizeAndInsets: nil, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
                return true
            }
        }
    }
    return false
}

public class ContactsController: ViewController {
    private let context: AccountContext
    
    private var contactsNode: ContactsControllerNode {
        return self.displayNode as! ContactsControllerNode
    }
    
    private let index: PeerNameIndex = .lastNameFirst
    
    private var _ready = Promise<Bool>()
    override public var ready: Promise<Bool> {
        return self._ready
    }
    
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    private var authorizationDisposable: Disposable?
    private let sortOrderPromise = Promise<ContactsSortOrder>()
    
    private var searchContentNode: NavigationBarSearchContentNode?
    
    var switchToChatsController: (() -> Void)?
    
    public init(context: AccountContext) {
        self.context = context
        
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBar.style.style
        
        self.title = self.presentationData.strings.Contacts_Title
        self.tabBarItem.title = self.presentationData.strings.Contacts_Title
        
        let icon: UIImage?
        if (useSpecialTabBarIcons()) {
            icon = UIImage(bundleImageName: "Chat List/Tabs/NY/IconContacts")
        } else {
            icon = UIImage(bundleImageName: "Chat List/Tabs/IconContacts")
        }
        
        self.tabBarItem.image = icon
        self.tabBarItem.selectedImage = icon
        
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(image: PresentationResourcesRootController.navigationAddIcon(self.presentationData.theme), style: .plain, target: self, action: #selector(self.addPressed))
        
        self.scrollToTop = { [weak self] in
            if let strongSelf = self {
                if let searchContentNode = strongSelf.searchContentNode {
                    searchContentNode.updateExpansionProgress(1.0, animated: true)
                }
                strongSelf.contactsNode.contactListNode.scrollToTop()
            }
        }
        
        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            if let strongSelf = self {
                let previousTheme = strongSelf.presentationData.theme
                let previousStrings = strongSelf.presentationData.strings
                
                strongSelf.presentationData = presentationData
                
                if previousTheme !== presentationData.theme || previousStrings !== presentationData.strings {
                    strongSelf.updateThemeAndStrings()
                }
            }
        })
        
        if #available(iOSApplicationExtension 10.0, iOS 10.0, *) {
            self.authorizationDisposable = (combineLatest(DeviceAccess.authorizationStatus(subject: .contacts), combineLatest(context.sharedContext.accountManager.noticeEntry(key: ApplicationSpecificNotice.contactsPermissionWarningKey()), context.account.postbox.preferencesView(keys: [PreferencesKeys.contactsSettings]), context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.contactSynchronizationSettings]))
            |> map { noticeView, preferences, sharedData -> (Bool, ContactsSortOrder) in
                let settings: ContactsSettings = preferences.values[PreferencesKeys.contactsSettings] as? ContactsSettings ?? ContactsSettings.defaultSettings
                let synchronizeDeviceContacts: Bool = settings.synchronizeContacts
                
                let contactsSettings = sharedData.entries[ApplicationSpecificSharedDataKeys.contactSynchronizationSettings] as? ContactSynchronizationSettings
                
                let sortOrder: ContactsSortOrder = contactsSettings?.sortOrder ?? .presence
                if !synchronizeDeviceContacts {
                    return (true, sortOrder)
                }
                let timestamp = noticeView.value.flatMap({ ApplicationSpecificNotice.getTimestampValue($0) })
                if let timestamp = timestamp, timestamp > 0 {
                    return (true, sortOrder)
                } else {
                    return (false, sortOrder)
                }
            })
            |> deliverOnMainQueue).start(next: { [weak self] status, suppressedAndSortOrder in
                if let strongSelf = self {
                    let (suppressed, sortOrder) = suppressedAndSortOrder
                    strongSelf.tabBarItem.badgeValue = status != .allowed && !suppressed ? "!" : nil
                    strongSelf.sortOrderPromise.set(.single(sortOrder))
                }
            })
        } else {
            self.sortOrderPromise.set(context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.contactSynchronizationSettings])
            |> map { sharedData -> ContactsSortOrder in
                let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.contactSynchronizationSettings] as? ContactSynchronizationSettings
                return settings?.sortOrder ?? .presence
            })
        }
        
        self.searchContentNode = NavigationBarSearchContentNode(theme: self.presentationData.theme, placeholder: self.presentationData.strings.Common_Search, activate: { [weak self] in
            self?.activateSearch()
        })
        self.navigationBar?.setContentNode(self.searchContentNode, animated: false)
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.presentationDataDisposable?.dispose()
        self.authorizationDisposable?.dispose()
    }
    
    private func updateThemeAndStrings() {
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBar.style.style
        self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: self.presentationData))
        self.searchContentNode?.updateThemeAndPlaceholder(theme: self.presentationData.theme, placeholder: self.presentationData.strings.Common_Search)
        self.title = self.presentationData.strings.Contacts_Title
        self.tabBarItem.title = self.presentationData.strings.Contacts_Title
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
        if self.navigationItem.rightBarButtonItem != nil {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(image: PresentationResourcesRootController.navigationAddIcon(self.presentationData.theme), style: .plain, target: self, action: #selector(self.addPressed))
        }
    }
    
    override public func loadDisplayNode() {
        self.displayNode = ContactsControllerNode(context: self.context, sortOrder: sortOrderPromise.get() |> distinctUntilChanged, present: { [weak self] c, a in
            self?.present(c, in: .window(.root), with: a)
        })
        self._ready.set(self.contactsNode.contactListNode.ready)
        
        self.contactsNode.navigationBar = self.navigationBar
        
        let openPeer: (ContactListPeer, Bool) -> Void = { [weak self] peer, fromSearch in
            if let strongSelf = self {
                switch peer {
                    case let .peer(peer, _, _):
                        if let navigationController = strongSelf.navigationController as? NavigationController {
                            navigateToChatController(navigationController: navigationController, context: strongSelf.context, chatLocation: .peer(peer.id), purposefulAction: { [weak self] in
                                if fromSearch {
                                    self?.deactivateSearch(animated: false)
                                    self?.switchToChatsController?()
                                }
                            }, completion: { [weak self] in
                                if let strongSelf = self {
                                    strongSelf.contactsNode.contactListNode.listNode.clearHighlightAnimated(true)
                                }
                            })
                        }
                    case let .deviceContact(id, _):
                        let _ = ((strongSelf.context.sharedContext.contactDataManager?.extendedData(stableId: id) ?? .single(nil))
                        |> take(1)
                        |> deliverOnMainQueue).start(next: { value in
                            guard let strongSelf = self, let value = value else {
                                return
                            }
                            (strongSelf.navigationController as? NavigationController)?.pushViewController(deviceContactInfoController(context: strongSelf.context, subject: .vcard(nil, id, value)), completion: { [weak self] in
                                if let strongSelf = self {
                                    strongSelf.contactsNode.contactListNode.listNode.clearHighlightAnimated(true)
                                }
                            })
                        })
                }
            }
        }
        
        self.contactsNode.requestDeactivateSearch = { [weak self] in
            self?.deactivateSearch(animated: true)
        }
        
        self.contactsNode.requestOpenPeerFromSearch = { peer in
            openPeer(peer, true)
        }
        
        self.contactsNode.contactListNode.openPrivacyPolicy = { [weak self] in
            if let strongSelf = self {
                openExternalUrl(context: strongSelf.context, urlContext: .generic, url: "https://telegram.org/privacy", forceExternal: true, presentationData: strongSelf.presentationData, navigationController: strongSelf.navigationController as? NavigationController, dismissInput: {})
            }
        }
        
        self.contactsNode.contactListNode.suppressPermissionWarning = { [weak self] in
            if let strongSelf = self {
                presentContactsWarningSuppression(context: strongSelf.context, present: { c, a in
                    strongSelf.present(c, in: .window(.root), with: a)
                })
            }
        }
        
        self.contactsNode.contactListNode.activateSearch = { [weak self] in
            self?.activateSearch()
        }
        
        self.contactsNode.contactListNode.openPeer = { peer in
            openPeer(peer, false)
        }
        
        self.contactsNode.openPeopleNearby = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            let _ = (DeviceAccess.authorizationStatus(context: strongSelf.context, subject: .location(.tracking))
            |> take(1)
            |> deliverOnMainQueue).start(next: { [weak self] status in
                guard let strongSelf = self else {
                    return
                }
                
                let presentPeersNearby = {
                    let controller = peersNearbyController(context: strongSelf.context)
                    (strongSelf.navigationController as? NavigationController)?.replaceAllButRootController(controller, animated: true, completion: { [weak self] in
                        if let strongSelf = self {
                            strongSelf.contactsNode.contactListNode.listNode.clearHighlightAnimated(true)
                        }
                    })
                }
                
                switch status {
                    case .allowed:
                        presentPeersNearby()
                    default:
                        let controller = PermissionController(context: strongSelf.context, splashScreen: false)
                        controller.setState(.nearbyLocation(status: PermissionRequestStatus(accessType: status)), animated: false)
                        controller.proceed = { result in
                            if result {
                                presentPeersNearby()
                            } else {
                                let _ = (strongSelf.navigationController as? NavigationController)?.popViewController(animated: true)
                            }
                        }
                        (strongSelf.navigationController as? NavigationController)?.pushViewController(controller, completion: { [weak self] in
                            if let strongSelf = self {
                                strongSelf.contactsNode.contactListNode.listNode.clearHighlightAnimated(true)
                            }
                        })
                }
            })
        }
        
        self.contactsNode.openInvite = { [weak self] in
            if let strongSelf = self {
                (strongSelf.navigationController as? NavigationController)?.pushViewController(InviteContactsController(context: strongSelf.context), completion: {
                    if let strongSelf = self {
                        strongSelf.contactsNode.contactListNode.listNode.clearHighlightAnimated(true)
                    }
                })
            }
        }
        
        self.contactsNode.contactListNode.openSortMenu = { [weak self] in
            self?.presentSortMenu()
        }
        
        self.contactsNode.contactListNode.contentOffsetChanged = { [weak self] offset in
            if let strongSelf = self, let searchContentNode = strongSelf.searchContentNode {
                var progress: CGFloat = 0.0
                switch offset {
                    case let .known(offset):
                        progress = max(0.0, (searchContentNode.nominalHeight - max(0.0, offset - 50.0))) / searchContentNode.nominalHeight
                    case .none:
                        progress = 1.0
                    default:
                        break
                }
                searchContentNode.updateExpansionProgress(progress)
            }
        }
        
        self.contactsNode.contactListNode.contentScrollingEnded = { [weak self] listView in
            if let strongSelf = self, let searchContentNode = strongSelf.searchContentNode {
                return fixListNodeScrolling(listView, searchNode: searchContentNode)
            } else {
                return false
            }
        }
        
        self.displayNodeDidLoad()
    }
    
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.contactsNode.contactListNode.enableUpdates = true
    }
    
    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        self.contactsNode.contactListNode.enableUpdates = false
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        self.contactsNode.containerLayoutUpdated(layout, navigationBarHeight: self.navigationInsetHeight, actualNavigationBarHeight: self.navigationHeight, transition: transition)
    }
    
    private func activateSearch() {
        if self.displayNavigationBar {
            if let searchContentNode = self.searchContentNode {
                self.contactsNode.activateSearch(placeholderNode: searchContentNode.placeholderNode)
            }
            self.setDisplayNavigationBar(false, transition: .animated(duration: 0.5, curve: .spring))
        }
    }
    
    private func deactivateSearch(animated: Bool) {
        if !self.displayNavigationBar {
            self.setDisplayNavigationBar(true, transition: animated ? .animated(duration: 0.5, curve: .spring) : .immediate)
            if let searchContentNode = self.searchContentNode {
                self.contactsNode.deactivateSearch(placeholderNode: searchContentNode.placeholderNode, animated: animated)
            }
        }
    }
    
    private func presentSortMenu() {
        let updateSortOrder: (ContactsSortOrder) -> Void = { [weak self] sortOrder in
            if let strongSelf = self {
                strongSelf.sortOrderPromise.set(.single(sortOrder))
                let _ = updateContactSettingsInteractively(accountManager: strongSelf.context.sharedContext.accountManager, { current -> ContactSynchronizationSettings in
                    var updated = current
                    updated.sortOrder = sortOrder
                    return updated
                }).start()
            }
        }
        
        let actionSheet = ActionSheetController(presentationTheme: self.presentationData.theme)
        var items: [ActionSheetItem] = []
        items.append(ActionSheetTextItem(title: self.presentationData.strings.Contacts_SortBy))
        items.append(ActionSheetButtonItem(title: self.presentationData.strings.Contacts_SortByName, color: .accent, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
            updateSortOrder(.natural)
        }))
        items.append(ActionSheetButtonItem(title: self.presentationData.strings.Contacts_SortByPresence, color: .accent, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
            updateSortOrder(.presence)
        }))
        actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: self.presentationData.strings.Common_Cancel, color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])])
        self.present(actionSheet, in: .window(.root))
    }
    
    @objc func addPressed() {
        let _ = (DeviceAccess.authorizationStatus(subject: .contacts)
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] status in
            guard let strongSelf = self else {
                return
            }
            
            switch status {
                case .allowed:
                    let contactData = DeviceContactExtendedData(basicData: DeviceContactBasicData(firstName: "", lastName: "", phoneNumbers: [DeviceContactPhoneNumberData(label: "_$!<Mobile>!$_", value: "+")]), middleName: "", prefix: "", suffix: "", organization: "", jobTitle: "", department: "", emailAddresses: [], urls: [], addresses: [], birthdayDate: nil, socialProfiles: [], instantMessagingProfiles: [])
                    strongSelf.present(deviceContactInfoController(context: strongSelf.context, subject: .create(peer: nil, contactData: contactData, isSharing: false, shareViaException: false, completion: { peer, stableId, contactData in
                        guard let strongSelf = self else {
                            return
                        }
                        if let peer = peer {
                            if let infoController = peerInfoController(context: strongSelf.context, peer: peer) {
                                (strongSelf.navigationController as? NavigationController)?.pushViewController(infoController)
                            }
                        } else {
                            (strongSelf.navigationController as? NavigationController)?.pushViewController(deviceContactInfoController(context: strongSelf.context, subject: .vcard(nil, stableId, contactData)))
                        }
                    })), in: .window(.root), with: ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
                case .notDetermined:
                    DeviceAccess.authorizeAccess(to: .contacts)
                default:
                    let presentationData = strongSelf.presentationData
                    strongSelf.present(textAlertController(context: strongSelf.context, title: presentationData.strings.AccessDenied_Title, text: presentationData.strings.Contacts_AccessDeniedError, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_NotNow, action: {}), TextAlertAction(type: .genericAction, title: presentationData.strings.AccessDenied_Settings, action: {
                        self?.context.sharedContext.applicationBindings.openSettings()
                    })]), in: .window(.root))
            }
        })
    }
}
