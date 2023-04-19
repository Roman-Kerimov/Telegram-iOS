import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext
import ItemListPeerItem
import ItemListPeerActionItem

private final class SelectivePrivacyPeersControllerArguments {
    let context: AccountContext
    
    let setPeerIdWithRevealedOptions: (EnginePeer.Id?, EnginePeer.Id?) -> Void
    let removePeer: (EnginePeer.Id) -> Void
    let addPeer: () -> Void
    let openPeer: (EnginePeer) -> Void
    let deleteAll: () -> Void
    
    init(context: AccountContext, setPeerIdWithRevealedOptions: @escaping (EnginePeer.Id?, EnginePeer.Id?) -> Void, removePeer: @escaping (EnginePeer.Id) -> Void, addPeer: @escaping () -> Void, openPeer: @escaping (EnginePeer) -> Void, deleteAll: @escaping () -> Void) {
        self.context = context
        self.setPeerIdWithRevealedOptions = setPeerIdWithRevealedOptions
        self.removePeer = removePeer
        self.addPeer = addPeer
        self.openPeer = openPeer
        self.deleteAll = deleteAll
    }
}

private enum SelectivePrivacyPeersSection: Int32 {
    case peers
    case delete
}

private enum SelectivePrivacyPeersEntryStableId: Hashable {
    case header
    case add
    case peer(EnginePeer.Id)
    case delete
}

private enum SelectivePrivacyPeersEntry: ItemListNodeEntry {
    case peerItem(Int32, PresentationTheme, PresentationStrings, PresentationDateTimeFormat, PresentationPersonNameOrder, SelectivePrivacyPeer, ItemListPeerItemEditing, Bool)
    case addItem(PresentationTheme, String, Bool)
    case headerItem(PresentationTheme, String)
    case deleteItem(PresentationTheme, String)
    
    var section: ItemListSectionId {
        switch self {
        case .addItem, .peerItem, .headerItem:
            return SelectivePrivacyPeersSection.peers.rawValue
        case .deleteItem:
            return SelectivePrivacyPeersSection.delete.rawValue
        }
    }
    
    var stableId: SelectivePrivacyPeersEntryStableId {
        switch self {
        case let .peerItem(_, _, _, _, _, peer, _, _):
            return .peer(peer.peer.id)
        case .addItem:
            return .add
        case .headerItem:
            return .header
        case .deleteItem:
            return .delete
        }
    }
    
    static func ==(lhs: SelectivePrivacyPeersEntry, rhs: SelectivePrivacyPeersEntry) -> Bool {
        switch lhs {
        case let .peerItem(lhsIndex, lhsTheme, lhsStrings, lhsDateTimeFormat, lhsNameOrder, lhsPeer, lhsEditing, lhsEnabled):
            if case let .peerItem(rhsIndex, rhsTheme, rhsStrings, rhsDateTimeFormat, rhsNameOrder, rhsPeer, rhsEditing, rhsEnabled) = rhs {
                if lhsIndex != rhsIndex {
                    return false
                }
                if lhsPeer != rhsPeer {
                    return false
                }
                if lhsTheme !== rhsTheme {
                    return false
                }
                if lhsStrings !== rhsStrings {
                    return false
                }
                if lhsDateTimeFormat != rhsDateTimeFormat {
                    return false
                }
                if lhsNameOrder != rhsNameOrder {
                    return false
                }
                if lhsEditing != rhsEditing {
                    return false
                }
                if lhsEnabled != rhsEnabled {
                    return false
                }
                return true
            } else {
                return false
            }
        case let .addItem(lhsTheme, lhsText, lhsEditing):
            if case let .addItem(rhsTheme, rhsText, rhsEditing) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsEditing == rhsEditing {
                return true
            } else {
                return false
            }
        case let .headerItem(lhsTheme, lhsText):
            if case let .headerItem(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            } else {
                return false
            }
        case let .deleteItem(lhsTheme, lhsText):
            if case let .deleteItem(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            } else {
                return false
            }
        }
    }
    
    static func <(lhs: SelectivePrivacyPeersEntry, rhs: SelectivePrivacyPeersEntry) -> Bool {
        switch lhs {
            case .deleteItem:
                return false
            case let .peerItem(index, _, _, _, _, _, _, _):
                switch rhs {
                    case .deleteItem:
                        return true
                    case let .peerItem(rhsIndex, _, _, _, _, _, _, _):
                        return index < rhsIndex
                    case .addItem, .headerItem:
                        return false
                }
            case .addItem:
                switch rhs {
                    case .peerItem, .deleteItem:
                        return true
                    case .headerItem:
                        return false
                    default:
                        return false
                }
            case .headerItem:
                return true
        }
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SelectivePrivacyPeersControllerArguments
        switch self {
        case let .peerItem(_, _, strings, dateTimeFormat, nameDisplayOrder, peer, editing, enabled):
            var text: ItemListPeerItemText = .none
            if let group = peer.peer as? TelegramGroup {
                text = .text(strings.Conversation_StatusMembers(Int32(group.participantCount)), .secondary)
            } else if let channel = peer.peer as? TelegramChannel {
                if let participantCount = peer.participantCount {
                    text = .text(strings.Conversation_StatusMembers(Int32(participantCount)), .secondary)
                } else {
                    switch channel.info {
                        case .group:
                            text = .text(strings.Group_Status, .secondary)
                        case .broadcast:
                            text = .text(strings.Channel_Status, .secondary)
                    }
                }
            }
            return ItemListPeerItem(presentationData: presentationData, dateTimeFormat: dateTimeFormat, nameDisplayOrder: nameDisplayOrder, context: arguments.context, peer: EnginePeer(peer.peer), presence: nil, text: text, label: .none, editing: editing, switchValue: nil, enabled: enabled, selectable: true, sectionId: self.section, action: {
                arguments.openPeer(EnginePeer(peer.peer))
            }, setPeerIdWithRevealedOptions: { previousId, id in
                arguments.setPeerIdWithRevealedOptions(previousId, id)
            }, removePeer: { peerId in
                arguments.removePeer(peerId)
            })
        case let .addItem(theme, text, editing):
            return ItemListPeerActionItem(presentationData: presentationData, icon: PresentationResourcesItemList.plusIconImage(theme), title: text, sectionId: self.section, height: .compactPeerList, editing: editing, action: {
                    arguments.addPeer()
                })
        case let .headerItem(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .deleteItem(_, text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .destructive, alignment: .center, sectionId: self.section, style: .blocks, action: {
                arguments.deleteAll()
            })
        }
    }
}

private struct SelectivePrivacyPeersControllerState: Equatable {
    let editing: Bool
    let peerIdWithRevealedOptions: EnginePeer.Id?
    
    init() {
        self.editing = false
        self.peerIdWithRevealedOptions = nil
    }
    
    init(editing: Bool, peerIdWithRevealedOptions: EnginePeer.Id?) {
        self.editing = editing
        self.peerIdWithRevealedOptions = peerIdWithRevealedOptions
    }
    
    static func ==(lhs: SelectivePrivacyPeersControllerState, rhs: SelectivePrivacyPeersControllerState) -> Bool {
        if lhs.editing != rhs.editing {
            return false
        }
        if lhs.peerIdWithRevealedOptions != rhs.peerIdWithRevealedOptions {
            return false
        }
        return true
    }
    
    func withUpdatedEditing(_ editing: Bool) -> SelectivePrivacyPeersControllerState {
        return SelectivePrivacyPeersControllerState(editing: editing, peerIdWithRevealedOptions: self.peerIdWithRevealedOptions)
    }
    
    func withUpdatedPeerIdWithRevealedOptions(_ peerIdWithRevealedOptions: EnginePeer.Id?) -> SelectivePrivacyPeersControllerState {
        return SelectivePrivacyPeersControllerState(editing: self.editing, peerIdWithRevealedOptions: peerIdWithRevealedOptions)
    }
}

private func selectivePrivacyPeersControllerEntries(presentationData: PresentationData, state: SelectivePrivacyPeersControllerState, peers: [SelectivePrivacyPeer]) -> [SelectivePrivacyPeersEntry] {
    var entries: [SelectivePrivacyPeersEntry] = []
    
    let title: String
    if peers.isEmpty {
        title = presentationData.strings.Privacy_Exceptions
    } else {
        title = presentationData.strings.Privacy_ExceptionsCount(Int32(peers.count))
    }
    entries.append(.headerItem(presentationData.theme, title))
    entries.append(.addItem(presentationData.theme, presentationData.strings.Privacy_AddNewPeer, state.editing))
    
    var index: Int32 = 0
    for peer in peers {
        entries.append(.peerItem(index, presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, presentationData.nameDisplayOrder, peer, ItemListPeerItemEditing(editable: true, editing: state.editing, revealed: peer.peer.id == state.peerIdWithRevealedOptions), true))
        index += 1
    }
    
    if !peers.isEmpty {
        entries.append(.deleteItem(presentationData.theme, presentationData.strings.Privacy_Exceptions_DeleteAllExceptions))
    }
    
    return entries
}

public func selectivePrivacyPeersController(context: AccountContext, title: String, initialPeers: [EnginePeer.Id: SelectivePrivacyPeer], updated: @escaping ([EnginePeer.Id: SelectivePrivacyPeer]) -> Void) -> ViewController {
    let statePromise = ValuePromise(SelectivePrivacyPeersControllerState(), ignoreRepeated: true)
    let stateValue = Atomic(value: SelectivePrivacyPeersControllerState())
    let updateState: ((SelectivePrivacyPeersControllerState) -> SelectivePrivacyPeersControllerState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }
    
    var dismissImpl: (() -> Void)?
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    
    let actionsDisposable = DisposableSet()
    
    let addPeerDisposable = MetaDisposable()
    actionsDisposable.add(addPeerDisposable)
    
    let removePeerDisposable = MetaDisposable()
    actionsDisposable.add(removePeerDisposable)
    
    let peersPromise = Promise<[SelectivePrivacyPeer]>()
    peersPromise.set(.single(Array(initialPeers.values)))
    
    let arguments = SelectivePrivacyPeersControllerArguments(context: context, setPeerIdWithRevealedOptions: { peerId, fromPeerId in
        updateState { state in
            if (peerId == nil && fromPeerId == state.peerIdWithRevealedOptions) || (peerId != nil && fromPeerId == nil) {
                return state.withUpdatedPeerIdWithRevealedOptions(peerId)
            } else {
                return state
            }
        }
    }, removePeer: { memberId in
        let applyPeers: Signal<Void, NoError> = peersPromise.get()
        |> take(1)
        |> deliverOnMainQueue
        |> mapToSignal { peers -> Signal<Void, NoError> in
            var updatedPeers = peers
            for i in 0 ..< updatedPeers.count {
                if updatedPeers[i].peer.id == memberId {
                    updatedPeers.remove(at: i)
                    break
                }
            }
            peersPromise.set(.single(updatedPeers))
            
            var updatedPeerDict: [EnginePeer.Id: SelectivePrivacyPeer] = [:]
            for peer in updatedPeers {
                updatedPeerDict[peer.peer.id] = peer
            }
            updated(updatedPeerDict)
            
            if updatedPeerDict.isEmpty {
                dismissImpl?()
            }
            
            return .complete()
        }
        
        removePeerDisposable.set(applyPeers.start())
    }, addPeer: {
        let controller = context.sharedContext.makeContactMultiselectionController(ContactMultiselectionControllerParams(context: context, mode: .peerSelection(searchChatList: true, searchGroups: true, searchChannels: false), options: []))
        addPeerDisposable.set((controller.result
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak controller] result in
            var peerIds: [ContactListPeerId] = []
            if case let .result(peerIdsValue, _) = result {
                peerIds = peerIdsValue
            }
            
            let applyPeers: Signal<Void, NoError> = peersPromise.get()
            |> take(1)
            |> mapToSignal { peers -> Signal<[SelectivePrivacyPeer], NoError> in
                let filteredPeerIds = peerIds.compactMap { peerId -> EnginePeer.Id? in
                    if case let .peer(value) = peerId {
                        return value
                    } else {
                        return nil
                    }
                }
                return context.engine.data.get(
                    EngineDataMap(filteredPeerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init)),
                    EngineDataMap(filteredPeerIds.map(TelegramEngine.EngineData.Item.Peer.ParticipantCount.init))
                )
                |> map { peerMap, participantCountMap -> [SelectivePrivacyPeer] in
                    var updatedPeers = peers
                    var existingIds = Set(updatedPeers.map { $0.peer.id })
                    for peerId in peerIds {
                        guard case let .peer(peerId) = peerId else {
                            continue
                        }
                        if let maybePeer = peerMap[peerId], let peer = maybePeer, !existingIds.contains(peerId) {
                            existingIds.insert(peerId)
                            var participantCount: Int32?
                            if case let .channel(channel) = peer, case .group = channel.info {
                                if let maybeParticipantCount = participantCountMap[peerId], let participantCountValue = maybeParticipantCount {
                                    participantCount = Int32(participantCountValue)
                                }
                            }
                            
                            updatedPeers.append(SelectivePrivacyPeer(peer: peer._asPeer(), participantCount: participantCount))
                        }
                    }
                    return updatedPeers
                }
            }
            |> deliverOnMainQueue
            |> mapToSignal { updatedPeers -> Signal<Void, NoError> in
                peersPromise.set(.single(updatedPeers))
                
                var updatedPeerDict: [EnginePeer.Id: SelectivePrivacyPeer] = [:]
                for peer in updatedPeers {
                    updatedPeerDict[peer.peer.id] = peer
                }
                updated(updatedPeerDict)
                
                return .complete()
            }
            
            removePeerDisposable.set(applyPeers.start())
            controller?.dismiss()
        }))
        presentControllerImpl?(controller, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }, openPeer: { peer in
        guard let controller = context.sharedContext.makePeerInfoController(context: context, updatedPresentationData: nil, peer: peer._asPeer(), mode: .generic, avatarInitiallyExpanded: false, fromChat: false, requestsContext: nil) else {
            return
        }
        pushControllerImpl?(controller)
    }, deleteAll: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        actionSheet.setItemGroups([ActionSheetItemGroup(items: [
            ActionSheetTextItem(title: presentationData.strings.Privacy_Exceptions_DeleteAllConfirmation),
            ActionSheetButtonItem(title: presentationData.strings.Privacy_Exceptions_DeleteAll, color: .destructive, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                
                let applyPeers: Signal<Void, NoError> = peersPromise.get()
                |> take(1)
                |> deliverOnMainQueue
                |> mapToSignal { _ -> Signal<Void, NoError> in
                    peersPromise.set(.single([]))
                    updated([:])
                    
                    dismissImpl?()

                    return .complete()
                }
                
                removePeerDisposable.set(applyPeers.start())
            })
        ]), ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])])
        presentControllerImpl?(actionSheet, nil)
    })
    
    var previousPeers: [SelectivePrivacyPeer]?
    
    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get(), peersPromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state, peers -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var rightNavigationButton: ItemListNavigationButton?
        if !peers.isEmpty {
            if state.editing {
                rightNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: true, action: {
                    updateState { state in
                        return state.withUpdatedEditing(false)
                    }
                })
            } else {
                rightNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Edit), style: .regular, enabled: true, action: {
                    updateState { state in
                        return state.withUpdatedEditing(true)
                    }
                })
            }
        }
        
        let previous = previousPeers
        previousPeers = peers
        
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: selectivePrivacyPeersControllerEntries(presentationData: presentationData, state: state, peers: peers), style: .blocks, emptyStateItem: nil, animateChanges: previous != nil && previous!.count >= peers.count)
        
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        actionsDisposable.dispose()
    }
    
    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        if let controller = controller, let navigationController = controller.navigationController as? NavigationController {
            navigationController.filterController(controller, animated: true)
        }
    }
    presentControllerImpl = { [weak controller] c, p in
        if let controller = controller {
            controller.present(c, in: .window(.root), with: p)
        }
    }
    pushControllerImpl = { [weak controller] c in
        if let navigationController = controller?.navigationController as? NavigationController {
            navigationController.pushViewController(c)
        }
    }
    return controller
}
