import Foundation
import AsyncDisplayKit

public enum ActionSheetButtonColor {
    case accent
    case destructive
    case disabled
}

public class ActionSheetButtonItem: ActionSheetItem {
    public let title: String
    public let color: ActionSheetButtonColor
    public let enabled: Bool
    public let action: () -> Void
    
    public init(title: String, color: ActionSheetButtonColor = .accent, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.enabled = enabled
        self.action = action
    }
    
    public func node() -> ActionSheetItemNode {
        let node = ActionSheetButtonNode()
        node.setItem(self)
        return node
    }
    
    public func updateNode(_ node: ActionSheetItemNode) {
        guard let node = node as? ActionSheetButtonNode else {
            assertionFailure()
            return
        }
        
        node.setItem(self)
    }
}

public class ActionSheetButtonNode: ActionSheetItemNode {
    public static let defaultFont: UIFont = Font.regular(20.0)
    
    private var item: ActionSheetButtonItem?
    
    private let button: HighlightTrackingButton
    private let label: ASTextNode
    
    override public init() {
        self.button = HighlightTrackingButton()
        
        self.label = ASTextNode()
        self.label.isLayerBacked = true
        self.label.maximumNumberOfLines = 1
        self.label.displaysAsynchronously = false
        
        super.init()
        
        self.view.addSubview(self.button)
        
        self.label.isUserInteractionEnabled = false
        self.addSubnode(self.label)
        
        self.button.highligthedChanged = { [weak self] highlighted in
            if let strongSelf = self {
                if highlighted {
                    strongSelf.backgroundNode.backgroundColor = ActionSheetItemNode.highlightedBackgroundColor
                } else {
                    UIView.animate(withDuration: 0.3, animations: {
                        strongSelf.backgroundNode.backgroundColor = ActionSheetItemNode.defaultBackgroundColor
                    })
                }
            }
        }
        
        self.button.addTarget(self, action: #selector(self.buttonPressed), for: .touchUpInside)
    }
    
    func setItem(_ item: ActionSheetButtonItem) {
        self.item = item
        
        let textColor: UIColor
        switch item.color {
            case .accent:
                textColor = UIColor(0x007ee5)
            case .destructive:
                textColor = .red
            case .disabled:
                textColor = .gray
        }
        self.label.attributedText = NSAttributedString(string: item.title, font: ActionSheetButtonNode.defaultFont, textColor: textColor)
        
        self.button.isEnabled = item.enabled
        
        self.setNeedsLayout()
    }
    
    public override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        return CGSize(width: constrainedSize.width, height: 57.0)
    }
    
    public override func layout() {
        super.layout()
        
        let size = self.bounds.size
        
        self.button.frame = CGRect(origin: CGPoint(), size: size)
        
        let labelSize = self.label.measure(size)
        self.label.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - labelSize.width) / 2.0), y: floorToScreenPixels((size.height - labelSize.height) / 2.0)), size: labelSize)
    }
    
    @objc func buttonPressed() {
        if let item = self.item {
            item.action()
        }
    }
}
