import Foundation

/// One image of a gallery opened for editing; keys the sheet does not edit go back to the editor unchanged.
public struct GalleryImage: Codable, Sendable, Equatable {
    public var id: Int?
    public var url: String
    public var fullUrl: String?
    public var alt: String
    public var caption: String
    public var captionHTML: String?
    public var sizeSlug: String?
    public var href: String?
    public var blockAttrs: String?
    public var extraClasses: String
    public var extraAttrs: String?

    public init(
        id: Int?, url: String, fullUrl: String?, alt: String, caption: String, captionHTML: String?,
        sizeSlug: String?, href: String?, blockAttrs: String?, extraClasses: String, extraAttrs: String? = nil
    ) {
        self.id = id
        self.url = url
        self.fullUrl = fullUrl
        self.alt = alt
        self.caption = caption
        self.captionHTML = captionHTML
        self.sizeSlug = sizeSlug
        self.href = href
        self.blockAttrs = blockAttrs
        self.extraClasses = extraClasses
        self.extraAttrs = extraAttrs
    }

    enum CodingKeys: String, CodingKey {
        case id, url, fullUrl, alt, caption, captionHTML, sizeSlug, href, blockAttrs, extraClasses, extraAttrs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        fullUrl = try c.decodeIfPresent(String.self, forKey: .fullUrl)
        alt = try c.decodeIfPresent(String.self, forKey: .alt) ?? ""
        caption = try c.decodeIfPresent(String.self, forKey: .caption) ?? ""
        captionHTML = try c.decodeIfPresent(String.self, forKey: .captionHTML)
        sizeSlug = try c.decodeIfPresent(String.self, forKey: .sizeSlug)
        href = try c.decodeIfPresent(String.self, forKey: .href)
        blockAttrs = try c.decodeIfPresent(String.self, forKey: .blockAttrs)
        extraClasses = try c.decodeIfPresent(String.self, forKey: .extraClasses) ?? ""
        extraAttrs = try c.decodeIfPresent(String.self, forKey: .extraAttrs)
    }
}

/// A gallery opened for editing; `linkTo` is WordPress's own value, `columns` nil for core's default.
public struct GalleryEdit: Codable, Sendable {
    public var images: [GalleryImage]
    public var columns: Int?
    public var cropped: Bool
    public var linkTo: String

    public init(images: [GalleryImage], columns: Int?, cropped: Bool, linkTo: String) {
        self.images = images
        self.columns = columns
        self.cropped = cropped
        self.linkTo = linkTo
    }

    /// Reads the `insertGallery` message body; nil for the toolbar's insert body `{}`.
    public init?(body: Any) {
        guard let edit = (body as? [String: Any])?["edit"],
              JSONSerialization.isValidJSONObject(edit),
              let data = try? JSONSerialization.data(withJSONObject: edit),
              let decoded = try? JSONDecoder().decode(GalleryEdit.self, from: data)
        else { return nil }
        self = decoded
    }

    public var initialSizeSlug: String {
        let sizes = Set(images.compactMap(\.sizeSlug))
        if sizes.count > 1 { return "mixed" }
        return sizes.first ?? "large"
    }

    public var showsKeepLinks: Bool {
        switch linkTo {
        case "none":
            return images.contains { $0.href != nil }
        case "media":
            return images.contains { image in
                guard let href = image.href else { return true }
                return href != image.fullUrl && href != image.url
            }
        default:
            return true
        }
    }
}

/// One presentation of `GallerySheet`; a new id per request gives the sheet fresh state.
struct GallerySheetRequest: Identifiable {
    let id = UUID()
    let editing: GalleryEdit?
}
