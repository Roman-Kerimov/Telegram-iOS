import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AvatarNode
import AccountContext
import PhoneNumberFormat
import TelegramStringFormatting
import Markdown
import ShimmerEffect
import AnimatedStickerNode
import TelegramAnimatedStickerNode
import ChatMessageDateAndStatusNode
import ChatMessageBubbleContentNode
import ChatMessageItemCommon
import ChatMessageAttachedContentButtonNode
import UndoUI

private let titleFont = Font.medium(15.0)
private let textFont = Font.regular(13.0)
private let boldTextFont = Font.semibold(13.0)

public class ChatMessageGiveawayBubbleContentNode: ChatMessageBubbleContentNode {
    private let dateAndStatusNode: ChatMessageDateAndStatusNode
    
    private let placeholderNode: StickerShimmerEffectNode
    private let animationNode: AnimatedStickerNode
    
    private let prizeTitleNode: TextNode
    private let prizeTextNode: TextNode
    
    private let participantsTitleNode: TextNode
    private let participantsTextNode: TextNode
    
    private let countriesTextNode: TextNode
    
    private let dateTitleNode: TextNode
    private let dateTextNode: TextNode
    
    private let badgeBackgroundNode: ASImageNode
    private let badgeTextNode: TextNode
    
    private var giveaway: TelegramMediaGiveaway?
    
    private let buttonNode: ChatMessageAttachedContentButtonNode
    private let channelButtons: PeerButtonsStackNode
    
    override public var visibility: ListViewItemNodeVisibility {
        didSet {
            let wasVisible = oldValue != .none
            let isVisible = self.visibility != .none
            
            if wasVisible != isVisible {
                self.visibilityStatus = isVisible
            }
        }
    }
    
    private var visibilityStatus: Bool? {
        didSet {
            if self.visibilityStatus != oldValue {
                self.updateVisibility()
            }
        }
    }
    
    private var setupTimestamp: Double?
    
    required public init() {
        self.placeholderNode = StickerShimmerEffectNode()
        self.placeholderNode.isUserInteractionEnabled = false
        self.placeholderNode.alpha = 0.75
        
        self.animationNode = DefaultAnimatedStickerNodeImpl()
        
        self.dateAndStatusNode = ChatMessageDateAndStatusNode()
        self.prizeTitleNode = TextNode()
        self.prizeTextNode = TextNode()
        
        self.participantsTitleNode = TextNode()
        self.participantsTextNode = TextNode()
        
        self.countriesTextNode = TextNode()
        
        self.dateTitleNode = TextNode()
        self.dateTextNode = TextNode()
        
        self.badgeBackgroundNode = ASImageNode()
        self.badgeBackgroundNode.displaysAsynchronously = false
        
        self.badgeTextNode = TextNode()
        
        self.buttonNode = ChatMessageAttachedContentButtonNode()
        self.channelButtons = PeerButtonsStackNode()
        
        super.init()
        
        self.addSubnode(self.prizeTitleNode)
        self.addSubnode(self.prizeTextNode)
        self.addSubnode(self.participantsTitleNode)
        self.addSubnode(self.participantsTextNode)
        self.addSubnode(self.countriesTextNode)
        self.addSubnode(self.dateTitleNode)
        self.addSubnode(self.dateTextNode)
        self.addSubnode(self.buttonNode)
        self.addSubnode(self.channelButtons)
        self.addSubnode(self.animationNode)
        self.addSubnode(self.badgeBackgroundNode)
        self.addSubnode(self.badgeTextNode)
        
        self.buttonNode.addTarget(self, action: #selector(self.buttonPressed), forControlEvents: .touchUpInside)
        
        self.dateAndStatusNode.reactionSelected = { [weak self] value in
            guard let strongSelf = self, let item = strongSelf.item else {
                return
            }
            item.controllerInteraction.updateMessageReaction(item.message, .reaction(value))
        }
        
        self.dateAndStatusNode.openReactionPreview = { [weak self] gesture, sourceView, value in
            guard let strongSelf = self, let item = strongSelf.item else {
                gesture?.cancel()
                return
            }
            
            item.controllerInteraction.openMessageReactionContextMenu(item.topMessage, sourceView, gesture, value)
        }
        
        self.channelButtons.openPeer = { [weak self] peer in
            guard let strongSelf = self, let item = strongSelf.item else {
                return
            }
            item.controllerInteraction.openPeer(peer, .chat(textInputState: nil, subject: nil, peekData: nil), nil, .default)
        }
    }
    
    override public func accessibilityActivate() -> Bool {
        self.buttonPressed()
        return true
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func didLoad() {
        super.didLoad()
        
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.bubbleTap(_:)))
        self.view.addGestureRecognizer(tapRecognizer)
    }
    
    @objc private func bubbleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        guard let item = self.item else {
            return
        }
        item.controllerInteraction.displayGiveawayParticipationStatus(item.message.id)
    }
    
    private func removePlaceholder(animated: Bool) {
        self.placeholderNode.alpha = 0.0
        if !animated {
            self.placeholderNode.removeFromSupernode()
        } else {
            self.placeholderNode.layer.animateAlpha(from: self.placeholderNode.alpha, to: 0.0, duration: 0.2, completion: { [weak self] _ in
                self?.placeholderNode.removeFromSupernode()
            })
        }
    }
    
    override public func asyncLayoutContent() -> (_ item: ChatMessageBubbleContentItem, _ layoutConstants: ChatMessageItemLayoutConstants, _ preparePosition: ChatMessageBubblePreparePosition, _ messageSelection: Bool?, _ constrainedSize: CGSize, _ avatarInset: CGFloat) -> (ChatMessageBubbleContentProperties, CGSize?, CGFloat, (CGSize, ChatMessageBubbleContentPosition) -> (CGFloat, (CGFloat) -> (CGSize, (ListViewItemUpdateAnimation, Bool, ListViewItemApply?) -> Void))) {
        let statusLayout = self.dateAndStatusNode.asyncLayout()
        let makePrizeTitleLayout = TextNode.asyncLayout(self.prizeTitleNode)
        let makePrizeTextLayout = TextNode.asyncLayout(self.prizeTextNode)
        
        let makeParticipantsTitleLayout = TextNode.asyncLayout(self.participantsTitleNode)
        let makeParticipantsTextLayout = TextNode.asyncLayout(self.participantsTextNode)
        
        let makeCountriesTextLayout = TextNode.asyncLayout(self.countriesTextNode)
        
        let makeDateTitleLayout = TextNode.asyncLayout(self.dateTitleNode)
        let makeDateTextLayout = TextNode.asyncLayout(self.dateTextNode)

        let makeBadgeTextLayout = TextNode.asyncLayout(self.badgeTextNode)

        let makeButtonLayout = ChatMessageAttachedContentButtonNode.asyncLayout(self.buttonNode)
        
        let makeChannelsLayout = PeerButtonsStackNode.asyncLayout(self.channelButtons)
                
        let currentItem = self.item
        
        return { item, layoutConstants, _, _, constrainedSize, _ in
            var giveaway: TelegramMediaGiveaway?
            for media in item.message.media {
                if let media = media as? TelegramMediaGiveaway {
                    giveaway = media;
                }
            }
            
            var themeUpdated = false
            if currentItem?.presentationData.theme.theme !== item.presentationData.theme.theme {
                themeUpdated = true
            }
            
            var incoming = item.message.effectivelyIncoming(item.context.account.peerId)
            if let subject = item.associatedData.subject, case let .messageOptions(_, _, info) = subject, case .forward = info {
                incoming = false
            }
            
            let backgroundColor = incoming ? item.presentationData.theme.theme.chat.message.incoming.bubble.withoutWallpaper.fill.first! : item.presentationData.theme.theme.chat.message.outgoing.bubble.withoutWallpaper.fill.first!
            let textColor = incoming ? item.presentationData.theme.theme.chat.message.incoming.primaryTextColor : item.presentationData.theme.theme.chat.message.outgoing.primaryTextColor
            let accentColor = incoming ? item.presentationData.theme.theme.chat.message.incoming.accentTextColor : item.presentationData.theme.theme.chat.message.outgoing.accentTextColor
            
            var updatedBadgeImage: UIImage?
            if themeUpdated {
                updatedBadgeImage = generateStretchableFilledCircleImage(diameter: 21.0, color: accentColor, strokeColor: backgroundColor, strokeWidth: 1.0 + UIScreenPixel, backgroundColor: nil)
            }
            
            let badgeString = NSAttributedString(string: "X\(giveaway?.quantity ?? 1)", font: Font.with(size: 10.0, design: .round , weight: .bold, traits: .monospacedNumbers), textColor: .white)
            
            let prizeTitleString = NSAttributedString(string: item.presentationData.strings.Chat_Giveaway_Message_PrizeTitle, font: titleFont, textColor: textColor)
            var prizeTextString: NSAttributedString?
            if let giveaway {
                prizeTextString = parseMarkdownIntoAttributedString(item.presentationData.strings.Chat_Giveaway_Message_PrizeText(
                    item.presentationData.strings.Chat_Giveaway_Message_Subscriptions(giveaway.quantity),
                    item.presentationData.strings.Chat_Giveaway_Message_Months(giveaway.months)
                ).string, attributes: MarkdownAttributes(
                    body: MarkdownAttributeSet(font: textFont, textColor: textColor),
                    bold: MarkdownAttributeSet(font: boldTextFont, textColor: textColor),
                    link: MarkdownAttributeSet(font: textFont, textColor: textColor),
                    linkAttribute: { url in
                        return ("URL", url)
                    }
                ), textAlignment: .center)
            }
            
            let participantsTitleString = NSAttributedString(string: item.presentationData.strings.Chat_Giveaway_Message_ParticipantsTitle, font: titleFont, textColor: textColor)
            let participantsText: String
            let countriesText: String
            
            if let giveaway {
                if giveaway.flags.contains(.onlyNewSubscribers) {
                    if giveaway.channelPeerIds.count > 1 {
                        participantsText = item.presentationData.strings.Chat_Giveaway_Message_ParticipantsNewMany
                    } else {
                        participantsText = item.presentationData.strings.Chat_Giveaway_Message_ParticipantsNew
                    }
                } else {
                    if giveaway.channelPeerIds.count > 1 {
                        participantsText = item.presentationData.strings.Chat_Giveaway_Message_ParticipantsMany
                    } else {
                        participantsText = item.presentationData.strings.Chat_Giveaway_Message_Participants
                    }
                }
                if !giveaway.countries.isEmpty {
                    let locale = localeWithStrings(item.presentationData.strings)
                    let countryNames = giveaway.countries.map { id in
                        if let countryName = locale.localizedString(forRegionCode: id) {
                            return "\(flagEmoji(countryCode: id))\u{feff}\(countryName)"
                        } else {
                            return id
                        }
                    }
                    var countries: String = ""
                    if countryNames.count == 1, let country = countryNames.first {
                        countries = country
                    } else {
                        for i in 0 ..< countryNames.count {
                            countries.append(countryNames[i])
                            if i == countryNames.count - 2 {
                                countries.append(item.presentationData.strings.Chat_Giveaway_Message_CountriesLastDelimiter)
                            } else if i < countryNames.count - 2 {
                                countries.append(item.presentationData.strings.Chat_Giveaway_Message_CountriesDelimiter)
                            }
                        }
                    }
                    countriesText = item.presentationData.strings.Chat_Giveaway_Message_CountriesFrom(countries).string
                } else {
                    countriesText = ""
                }
            } else {
                participantsText = ""
                countriesText = ""
            }
                
            let participantsTextString = NSAttributedString(string: participantsText, font: textFont, textColor: textColor)
            
            let countriesTextString = NSAttributedString(string: countriesText, font: textFont, textColor: textColor)
            
            let dateTitleString = NSAttributedString(string: item.presentationData.strings.Chat_Giveaway_Message_DateTitle, font: titleFont, textColor: textColor)
            var dateTextString: NSAttributedString?
            if let giveaway {
                dateTextString = NSAttributedString(string: stringForFullDate(timestamp: giveaway.untilDate, strings: item.presentationData.strings, dateTimeFormat: item.presentationData.dateTimeFormat), font: textFont, textColor: textColor)
            }
            let contentProperties = ChatMessageBubbleContentProperties(hidesSimpleAuthorHeader: true, headerSpacing: 0.0, hidesBackground: .never, forceFullCorners: false, forceAlignment: .none)
            
            return (contentProperties, nil, CGFloat.greatestFiniteMagnitude, { constrainedSize, position in
                let sideInsets = layoutConstants.text.bubbleInsets.right * 2.0
                let maxTextWidth = min(200.0, max(1.0, constrainedSize.width - 7.0 - sideInsets))
                
                let (badgeTextLayout, badgeTextApply) = makeBadgeTextLayout(TextNodeLayoutArguments(attributedString: badgeString, backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: maxTextWidth, height: CGFloat.greatestFiniteMagnitude), alignment: .center, cutout: nil, insets: UIEdgeInsets()))
                
                let (prizeTitleLayout, prizeTitleApply) = makePrizeTitleLayout(TextNodeLayoutArguments(attributedString: prizeTitleString, backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: maxTextWidth, height: CGFloat.greatestFiniteMagnitude), alignment: .center, cutout: nil, insets: UIEdgeInsets()))
                                
                let (prizeTextLayout, prizeTextApply) = makePrizeTextLayout(TextNodeLayoutArguments(attributedString: prizeTextString, backgroundColor: nil, maximumNumberOfLines: 5, truncationType: .end, constrainedSize: CGSize(width: maxTextWidth, height: CGFloat.greatestFiniteMagnitude), alignment: .center, cutout: nil, insets: UIEdgeInsets()))
                
                let (participantsTitleLayout, participantsTitleApply) = makeParticipantsTitleLayout(TextNodeLayoutArguments(attributedString: participantsTitleString, backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: maxTextWidth, height: CGFloat.greatestFiniteMagnitude), alignment: .center, cutout: nil, insets: UIEdgeInsets()))
                let (participantsTextLayout, participantsTextApply) = makeParticipantsTextLayout(TextNodeLayoutArguments(attributedString: participantsTextString, backgroundColor: nil, maximumNumberOfLines: 5, truncationType: .end, constrainedSize: CGSize(width: maxTextWidth, height: CGFloat.greatestFiniteMagnitude), alignment: .center, cutout: nil, insets: UIEdgeInsets()))
                
                let (countriesTextLayout, countriesTextApply) = makeCountriesTextLayout(TextNodeLayoutArguments(attributedString: countriesTextString, backgroundColor: nil, maximumNumberOfLines: 5, truncationType: .end, constrainedSize: CGSize(width: maxTextWidth, height: CGFloat.greatestFiniteMagnitude), alignment: .center, cutout: nil, insets: UIEdgeInsets()))
                
                let (dateTitleLayout, dateTitleApply) = makeDateTitleLayout(TextNodeLayoutArguments(attributedString: dateTitleString, backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: maxTextWidth, height: CGFloat.greatestFiniteMagnitude), alignment: .center, cutout: nil, insets: UIEdgeInsets()))
                let (dateTextLayout, dateTextApply) = makeDateTextLayout(TextNodeLayoutArguments(attributedString: dateTextString, backgroundColor: nil, maximumNumberOfLines: 5, truncationType: .end, constrainedSize: CGSize(width: maxTextWidth, height: CGFloat.greatestFiniteMagnitude), alignment: .center, cutout: nil, insets: UIEdgeInsets()))
                
                var edited = false
                if item.attributes.updatingMedia != nil {
                    edited = true
                }
                var viewCount: Int?
                var dateReplies = 0
                var dateReactionsAndPeers = mergedMessageReactionsAndPeers(accountPeer: item.associatedData.accountPeer, message: item.message)
                if item.message.isRestricted(platform: "ios", contentSettings: item.context.currentContentSettings.with { $0 }) {
                    dateReactionsAndPeers = ([], [])
                }
                for attribute in item.message.attributes {
                    if let attribute = attribute as? EditedMessageAttribute {
                        edited = !attribute.isHidden
                    } else if let attribute = attribute as? ViewCountMessageAttribute {
                        viewCount = attribute.count
                    } else if let attribute = attribute as? ReplyThreadMessageAttribute, case .peer = item.chatLocation {
                        if let channel = item.message.peers[item.message.id.peerId] as? TelegramChannel, case .group = channel.info {
                            dateReplies = Int(attribute.count)
                        }
                    }
                }
                
                let dateText = stringForMessageTimestampStatus(accountPeerId: item.context.account.peerId, message: item.message, dateTimeFormat: item.presentationData.dateTimeFormat, nameDisplayOrder: item.presentationData.nameDisplayOrder, strings: item.presentationData.strings, associatedData: item.associatedData)
                
                let statusType: ChatMessageDateAndStatusType?
                switch position {
                    case .linear(_, .None), .linear(_, .Neighbour(true, _, _)):
                        if incoming {
                            statusType = .BubbleIncoming
                        } else {
                            if item.message.flags.contains(.Failed) {
                                statusType = .BubbleOutgoing(.Failed)
                            } else if (item.message.flags.isSending && !item.message.isSentOrAcknowledged) || item.attributes.updatingMedia != nil {
                                statusType = .BubbleOutgoing(.Sending)
                            } else {
                                statusType = .BubbleOutgoing(.Sent(read: item.read))
                            }
                        }
                    default:
                        statusType = nil
                }
                
                var statusSuggestedWidthAndContinue: (CGFloat, (CGFloat) -> (CGSize, (ListViewItemUpdateAnimation) -> Void))?
                if let statusType = statusType {
                    var isReplyThread = false
                    if case .replyThread = item.chatLocation {
                        isReplyThread = true
                    }
                    
                    statusSuggestedWidthAndContinue = statusLayout(ChatMessageDateAndStatusNode.Arguments(
                        context: item.context,
                        presentationData: item.presentationData,
                        edited: edited,
                        impressionCount: viewCount,
                        dateText: dateText,
                        type: statusType,
                        layoutInput: .trailingContent(contentWidth: 1000.0, reactionSettings: shouldDisplayInlineDateReactions(message: item.message, isPremium: item.associatedData.isPremium, forceInline: item.associatedData.forceInlineReactions) ? ChatMessageDateAndStatusNode.TrailingReactionSettings(displayInline: true, preferAdditionalInset: false) : nil),
                        constrainedSize: CGSize(width: constrainedSize.width - sideInsets, height: .greatestFiniteMagnitude),
                        availableReactions: item.associatedData.availableReactions,
                        reactions: dateReactionsAndPeers.reactions,
                        reactionPeers: dateReactionsAndPeers.peers,
                        displayAllReactionPeers: item.message.id.peerId.namespace == Namespaces.Peer.CloudUser,
                        replyCount: dateReplies,
                        isPinned: item.message.tags.contains(.pinned) && !item.associatedData.isInPinnedListMode && isReplyThread,
                        hasAutoremove: item.message.isSelfExpiring,
                        canViewReactionList: canViewMessageReactionList(message: item.message),
                        animationCache: item.controllerInteraction.presentationContext.animationCache,
                        animationRenderer: item.controllerInteraction.presentationContext.animationRenderer
                    ))
                }
                
                let titleColor: UIColor
                if incoming {
                    titleColor = item.presentationData.theme.theme.chat.message.incoming.accentTextColor
                } else {
                    titleColor = item.presentationData.theme.theme.chat.message.outgoing.accentTextColor
                }
                
                let (buttonWidth, continueLayout) = makeButtonLayout(constrainedSize.width, nil, false, item.presentationData.strings.Chat_Giveaway_Message_LearnMore.uppercased(), titleColor, false, true)
                
                let months = giveaway?.months ?? 0
                let animationName: String
                switch months {
                case 12:
                    animationName = "Gift12"
                case 6:
                    animationName = "Gift6"
                case 3:
                    animationName = "Gift3"
                default:
                    animationName = "Gift3"
                }
                
                var maxContentWidth: CGFloat = 0.0
                if let statusSuggestedWidthAndContinue = statusSuggestedWidthAndContinue {
                    maxContentWidth = max(maxContentWidth, statusSuggestedWidthAndContinue.0)
                }
                maxContentWidth = max(maxContentWidth, prizeTitleLayout.size.width)
                maxContentWidth = max(maxContentWidth, prizeTextLayout.size.width)
                maxContentWidth = max(maxContentWidth, participantsTitleLayout.size.width)
                maxContentWidth = max(maxContentWidth, participantsTextLayout.size.width)
                maxContentWidth = max(maxContentWidth, dateTitleLayout.size.width)
                maxContentWidth = max(maxContentWidth, dateTextLayout.size.width)
                maxContentWidth = max(maxContentWidth, buttonWidth)

                var channelPeers: [EnginePeer] = []
                if let channelPeerIds = giveaway?.channelPeerIds {
                    for peerId in channelPeerIds {
                        if let peer = item.message.peers[peerId] {
                            channelPeers.append(EnginePeer(peer))
                        }
                    }
                }
                let (channelsWidth, continueChannelLayout) = makeChannelsLayout(item.context, 240.0, channelPeers, accentColor, accentColor.withAlphaComponent(0.1))
                maxContentWidth = max(maxContentWidth, channelsWidth)
                maxContentWidth += 30.0
                
                let contentWidth = maxContentWidth + layoutConstants.text.bubbleInsets.right * 2.0
                
                return (contentWidth, { boundingWidth in
                    let (buttonSize, buttonApply) = continueLayout(boundingWidth - layoutConstants.text.bubbleInsets.right * 2.0, 33.0)
                    let buttonSpacing: CGFloat = 4.0
                    
                    let (channelButtonsSize, channelButtonsApply) = continueChannelLayout(boundingWidth - layoutConstants.text.bubbleInsets.right * 2.0)
                    
                    let statusSizeAndApply = statusSuggestedWidthAndContinue?.1(boundingWidth - sideInsets)
                    
                    var layoutSize = CGSize(width: contentWidth, height: 49.0 + prizeTitleLayout.size.height + prizeTextLayout.size.height + participantsTitleLayout.size.height + participantsTextLayout.size.height + dateTitleLayout.size.height + dateTextLayout.size.height + buttonSize.height + buttonSpacing + 120.0)
                    
                    if countriesTextLayout.size.height > 0.0 {
                        layoutSize.height += countriesTextLayout.size.height + 7.0
                    }
                    layoutSize.height += channelButtonsSize.height
                    
                    if let statusSizeAndApply = statusSizeAndApply {
                        layoutSize.height += statusSizeAndApply.0.height - 4.0
                    }
                    let buttonFrame = CGRect(origin: CGPoint(x: layoutConstants.text.bubbleInsets.right, y: layoutSize.height - 9.0 - buttonSize.height), size: buttonSize)
                    
                    return (layoutSize, { [weak self] animation, synchronousLoads, _ in
                        if let strongSelf = self {
                            if strongSelf.item == nil {
                                strongSelf.animationNode.autoplay = true
                                strongSelf.animationNode.setup(source: AnimatedStickerNodeLocalFileSource(name: animationName), width: 384, height: 384, playbackMode: .still(.start), mode: .direct(cachePathPrefix: nil))
                            }
                            strongSelf.item = item
                            strongSelf.giveaway = giveaway
                            
                            strongSelf.updateVisibility()
                                                        
                            let _ = badgeTextApply()
                            let _ = prizeTitleApply()
                            let _ = prizeTextApply()
                            let _ = participantsTitleApply()
                            let _ = participantsTextApply()
                            let _ = countriesTextApply()
                            let _ = dateTitleApply()
                            let _ = dateTextApply()
                            let _ = channelButtonsApply()
                            let _ = buttonApply(animation)
                            
                            let smallSpacing: CGFloat = 2.0
                            let largeSpacing: CGFloat = 14.0
                            
                            var originY: CGFloat = 0.0
                            
                            let iconSize = CGSize(width: 140.0, height: 140.0)
                            strongSelf.animationNode.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((layoutSize.width - iconSize.width) / 2.0), y: originY - 40.0), size: iconSize)
                            strongSelf.animationNode.updateLayout(size: iconSize)
                            
                            let badgeTextFrame = CGRect(origin: CGPoint(x: floorToScreenPixels((layoutSize.width - badgeTextLayout.size.width) / 2.0) + 1.0, y: originY + 88.0), size: badgeTextLayout.size)
                            strongSelf.badgeTextNode.frame = badgeTextFrame
                            strongSelf.badgeBackgroundNode.frame = badgeTextFrame.insetBy(dx: -6.0, dy: -5.0).offsetBy(dx: -1.0, dy: 0.0)
                            if let updatedBadgeImage {
                                strongSelf.badgeBackgroundNode.image = updatedBadgeImage
                            }
                            
                            originY += 112.0
                                                        
                            strongSelf.prizeTitleNode.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((layoutSize.width - prizeTitleLayout.size.width) / 2.0), y: originY), size: prizeTitleLayout.size)
                            originY += prizeTitleLayout.size.height + smallSpacing
                            strongSelf.prizeTextNode.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((layoutSize.width - prizeTextLayout.size.width) / 2.0), y: originY), size: prizeTextLayout.size)
                            originY += prizeTextLayout.size.height + largeSpacing
                            
                            strongSelf.participantsTitleNode.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((layoutSize.width - participantsTitleLayout.size.width) / 2.0), y: originY), size: participantsTitleLayout.size)
                            originY += participantsTitleLayout.size.height + smallSpacing
                            strongSelf.participantsTextNode.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((layoutSize.width - participantsTextLayout.size.width) / 2.0), y: originY), size: participantsTextLayout.size)
                            originY += participantsTextLayout.size.height + smallSpacing * 2.0 + 3.0
                            
                            strongSelf.channelButtons.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((layoutSize.width - channelButtonsSize.width) / 2.0), y: originY), size: channelButtonsSize)
                            originY += channelButtonsSize.height
                            
                            if countriesTextLayout.size.height > 0.0 {
                                originY += smallSpacing * 2.0 + 3.0
                                strongSelf.countriesTextNode.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((layoutSize.width - countriesTextLayout.size.width) / 2.0), y: originY), size: countriesTextLayout.size)
                                originY += countriesTextLayout.size.height
                            }
                            originY += largeSpacing
                            
                            strongSelf.dateTitleNode.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((layoutSize.width - dateTitleLayout.size.width) / 2.0), y: originY), size: dateTitleLayout.size)
                            originY += dateTitleLayout.size.height + smallSpacing
                            strongSelf.dateTextNode.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((layoutSize.width - dateTextLayout.size.width) / 2.0), y: originY), size: dateTextLayout.size)
                            originY += dateTextLayout.size.height + largeSpacing
                            
                            strongSelf.buttonNode.frame = buttonFrame
                            
                            if let statusSizeAndApply = statusSizeAndApply {
                                strongSelf.dateAndStatusNode.frame = CGRect(origin: CGPoint(x: layoutConstants.text.bubbleInsets.left, y: strongSelf.dateTextNode.frame.maxY + 2.0), size: statusSizeAndApply.0)
                                if strongSelf.dateAndStatusNode.supernode == nil {
                                    strongSelf.addSubnode(strongSelf.dateAndStatusNode)
                                    statusSizeAndApply.1(.None)
                                } else {
                                    statusSizeAndApply.1(animation)
                                }
                            } else if strongSelf.dateAndStatusNode.supernode != nil {
                                strongSelf.dateAndStatusNode.removeFromSupernode()
                            }
                                                        
                            if let forwardInfo = item.message.forwardInfo, forwardInfo.flags.contains(.isImported) {
                                strongSelf.dateAndStatusNode.pressed = {
                                    guard let strongSelf = self else {
                                        return
                                    }
                                    item.controllerInteraction.displayImportedMessageTooltip(strongSelf.dateAndStatusNode)
                                }
                            } else {
                                strongSelf.dateAndStatusNode.pressed = nil
                            }
                            
                            if let (rect, size) = strongSelf.absoluteRect {
                                strongSelf.updateAbsoluteRect(rect, within: size)
                            }
                        }
                    })
                })
            })
        }
    }
    
    private func updateVisibility() {
    }
    
    private var absoluteRect: (CGRect, CGSize)?
    override public func updateAbsoluteRect(_ rect: CGRect, within containerSize: CGSize) {
        self.absoluteRect = (rect, containerSize)
        
        self.placeholderNode.updateAbsoluteRect(CGRect(origin: CGPoint(x: rect.minX + self.placeholderNode.frame.minX, y: rect.minY + self.placeholderNode.frame.minY), size: self.placeholderNode.frame.size), within: containerSize)
    }
    
    override public func animateInsertion(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
    }
    
    override public func animateAdded(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
    }
    
    override public func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
    }
    
    override public func tapActionAtPoint(_ point: CGPoint, gesture: TapLongTapOrDoubleTapGesture, isEstimating: Bool) -> ChatMessageBubbleContentTapAction {
        if self.channelButtons.frame.contains(point) {
            return ChatMessageBubbleContentTapAction(content: .ignore)
        }
        if self.buttonNode.frame.contains(point) {
            return ChatMessageBubbleContentTapAction(content: .ignore)
        }
        if self.dateAndStatusNode.supernode != nil, let _ = self.dateAndStatusNode.hitTest(self.view.convert(point, to: self.dateAndStatusNode.view), with: nil) {
            return ChatMessageBubbleContentTapAction(content: .ignore)
        }
        return ChatMessageBubbleContentTapAction(content: .none)
    }

    @objc private func buttonPressed() {
        if let item = self.item {
            let _ = item.controllerInteraction.openMessage(item.message, .default)
        }
    }
    
    override public func reactionTargetView(value: MessageReaction.Reaction) -> UIView? {
        if !self.dateAndStatusNode.isHidden {
            return self.dateAndStatusNode.reactionView(value: value)
        }
        return nil
    }
    
    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if self.dateAndStatusNode.supernode != nil, let result = self.dateAndStatusNode.hitTest(self.view.convert(point, to: self.dateAndStatusNode.view), with: event) {
            return result
        }
        return super.hitTest(point, with: event)
    }
}

private final class PeerButtonsStackNode: ASDisplayNode {
    var buttonNodes: [PeerButtonNode] = []
    var openPeer: (EnginePeer) -> Void = { _ in }
    
    static func asyncLayout(_ current: PeerButtonsStackNode) -> (_ context: AccountContext, _ width: CGFloat, _ peers: [EnginePeer], _ titleColor: UIColor, _ backgroundColor: UIColor) -> (CGFloat, (CGFloat) -> (CGSize, () -> PeerButtonsStackNode)) {
        let currentChannelButtons = current.buttonNodes.isEmpty ? nil : current.buttonNodes
        let maybeMakeChannelButtons = current.buttonNodes.map(PeerButtonNode.asyncLayout)
        
        return { context, width, peers, titleColor, backgroundColor in
            let targetNode = current
            
            var buttonNodes: [PeerButtonNode] = []
            let makeChannelButtonLayouts: [(_ context: AccountContext, _ width: CGFloat, _ peer: EnginePeer?, _ titleColor: UIColor, _ backgroundColor: UIColor) -> (CGFloat, (CGFloat) -> (CGSize, () -> PeerButtonNode))]
            if let currentChannelButtons {
                buttonNodes = currentChannelButtons
                makeChannelButtonLayouts = maybeMakeChannelButtons
            } else {
                for _ in peers {
                    buttonNodes.append(PeerButtonNode())
                }
                makeChannelButtonLayouts = buttonNodes.map(PeerButtonNode.asyncLayout)
            }
            
            var maxWidth = 0.0
            let buttonHeight: CGFloat = 24.0
            let horizontalButtonSpacing: CGFloat = 4.0
            let verticalButtonSpacing: CGFloat = 6.0
     
            var sizes: [CGSize] = []
            var groups: [[Int]] = []
            var currentGroup: [Int] = []
            
            var buttonContinues: [(CGFloat) -> (CGSize, () -> PeerButtonNode)] = []
            for i in 0 ..< makeChannelButtonLayouts.count {
                let peer = peers[i]
                let makeChannelButtonLayout = makeChannelButtonLayouts[i]
                
                let (buttonWidth, buttonContinue) = makeChannelButtonLayout(context, width, peer, titleColor, backgroundColor)
                sizes.append(CGSize(width: buttonWidth, height: buttonHeight))
                buttonContinues.append(buttonContinue)
                
                var itemsWidth: CGFloat = 0.0
                for j in currentGroup {
                    itemsWidth += sizes[j].width
                }
                itemsWidth += buttonWidth
                itemsWidth += CGFloat(currentGroup.count) * horizontalButtonSpacing
                
                if itemsWidth > width {
                    groups.append(currentGroup)
                    currentGroup = []
                }
                currentGroup.append(i)
            }
            if !currentGroup.isEmpty {
                groups.append(currentGroup)
            }
            
            var rowWidths: [CGFloat] = []
            for group in groups {
                var rowWidth: CGFloat = 0.0
                for i in group {
                    let buttonSize = sizes[i]
                    rowWidth += buttonSize.width
                }
                rowWidth += CGFloat(currentGroup.count) * horizontalButtonSpacing
                
                if rowWidth > maxWidth {
                    maxWidth = rowWidth
                }
                rowWidths.append(rowWidth)
            }
            
            var frames: [CGRect] = []
            var originY: CGFloat = 0.0
            for i in 0 ..< groups.count {
                let rowWidth = rowWidths[i]
                var originX = floorToScreenPixels((maxWidth - rowWidth) / 2.0)
                
                for i in groups[i] {
                    let buttonSize = sizes[i]
                    frames.append(CGRect(origin: CGPoint(x: originX, y: originY), size: buttonSize))
                    originX += buttonSize.width + horizontalButtonSpacing
                }
                originY += buttonHeight + verticalButtonSpacing
            }
            
            return (maxWidth, { _ in
                var buttonLayoutsAndApply: [(CGSize, () -> PeerButtonNode)] = []
                for buttonApply in buttonContinues {
                    buttonLayoutsAndApply.append(buttonApply(maxWidth))
                }
                
                return (CGSize(width: maxWidth, height: originY - verticalButtonSpacing), {
                    targetNode.buttonNodes = buttonNodes
                    
                    for i in 0 ..< buttonNodes.count {
                        let peer = peers[i]
                        let buttonNode = buttonNodes[i]
                        buttonNode.pressed = { [weak targetNode] in
                            targetNode?.openPeer(peer)
                        }
                        if buttonNode.supernode == nil {
                            targetNode.addSubnode(buttonNode)
                        }
                        let frame = frames[i]
                        buttonNode.frame = frame
                    }
                    
                    for (_, apply) in buttonLayoutsAndApply {
                        let _ = apply()
                    }

                    return targetNode
                })
            })
        }
    }
}

private final class PeerButtonNode: HighlightTrackingButtonNode {
    private let backgroundNode: ASImageNode
    private let textNode: TextNode
    private let avatarNode: AvatarNode
    
    var currentBackgroundColor: UIColor?
    var pressed: (() -> Void)?
      
    init() {
        self.textNode = TextNode()
        self.textNode.isUserInteractionEnabled = false
      
        self.backgroundNode = ASImageNode()
        self.backgroundNode.isLayerBacked = true
        self.backgroundNode.displayWithoutProcessing = true
        self.backgroundNode.displaysAsynchronously = false
        
        self.avatarNode = AvatarNode(font: avatarPlaceholderFont(size: 14.0))
        
        super.init()
        
        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.textNode)
        self.addSubnode(self.avatarNode)
        
        self.highligthedChanged = { [weak self] highlighted in
            if let strongSelf = self {
                if highlighted {
                    strongSelf.layer.removeAnimation(forKey: "opacity")
                    strongSelf.alpha = 0.4
                } else {
                    strongSelf.alpha = 1.0
                    strongSelf.layer.animateAlpha(from: 0.4, to: 1.0, duration: 0.2)
                }
            }
        }
        
        self.addTarget(self, action: #selector(self.buttonPressed), forControlEvents: .touchUpInside)
    }
    
    @objc func buttonPressed() {
        self.pressed?()
    }
        
    static func asyncLayout(_ current: PeerButtonNode?) -> (_ context: AccountContext, _ width: CGFloat, _ peer: EnginePeer?, _ titleColor: UIColor, _ backgroundColor: UIColor) -> (CGFloat, (CGFloat) -> (CGSize, () -> PeerButtonNode)) {
        let maybeMakeTextLayout = (current?.textNode).flatMap(TextNode.asyncLayout)
        
        return { context, width, peer, titleColor, backgroundColor in
            let targetNode: PeerButtonNode
            if let current = current {
                targetNode = current
            } else {
                targetNode = PeerButtonNode()
            }
            
            let makeTextLayout: (TextNodeLayoutArguments) -> (TextNodeLayout, () -> TextNode)
            if let maybeMakeTextLayout = maybeMakeTextLayout {
                makeTextLayout = maybeMakeTextLayout
            } else {
                makeTextLayout = TextNode.asyncLayout(targetNode.textNode)
            }
                        
            let inset: CGFloat = 1.0
            let avatarSize = CGSize(width: 22.0, height: 22.0)
            let spacing: CGFloat = 5.0
            
            let (textSize, textApply) = makeTextLayout(TextNodeLayoutArguments(attributedString: NSAttributedString(string: peer?.compactDisplayTitle ?? "", font: Font.medium(14.0), textColor: titleColor), backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: max(1.0, width - avatarSize.width - (spacing + inset) * 2.0), height: CGFloat.greatestFiniteMagnitude), alignment: .left, cutout: nil, insets: UIEdgeInsets()))
            
            let refinedWidth = avatarSize.width + textSize.size.width + (spacing + inset) * 2.0
            return (refinedWidth, { _ in
                return (CGSize(width: refinedWidth, height: 24.0), {
                    let _ = textApply()
                    
                    let backgroundFrame = CGRect(origin: .zero, size: CGSize(width: refinedWidth, height: 24.0))
                    let textFrame = CGRect(origin: CGPoint(x: inset + avatarSize.width + spacing, y: floorToScreenPixels((backgroundFrame.height - textSize.size.height) / 2.0)), size: textSize.size)
                    targetNode.backgroundNode.frame = backgroundFrame
                    
                    if targetNode.currentBackgroundColor != backgroundColor {
                        targetNode.currentBackgroundColor = backgroundColor
                        targetNode.backgroundNode.image = generateStretchableFilledCircleImage(radius: 12.0, color: backgroundColor, backgroundColor: nil)
                    }
                    
                    targetNode.avatarNode.setPeer(
                        context: context,
                        theme: context.sharedContext.currentPresentationData.with({ $0 }).theme,
                        peer: peer,
                        synchronousLoad: false
                    )
                    targetNode.avatarNode.frame = CGRect(origin: CGPoint(x: inset, y: inset), size: avatarSize)
                    
                    targetNode.textNode.frame = textFrame
                    
                    return targetNode
                })
            })
        }
    }
}
