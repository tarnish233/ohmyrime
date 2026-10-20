//
//  Update.swift
//  鼠须管设置
//
//  Looking for a newer ohmyrime on GitHub: which version is the latest, and whether it is newer
//  than this one. Discovery follows GitHub's `releases/latest` redirect rather than the REST API,
//  which is rate limited per IP address and would make every installed copy compete for the same
//  anonymous quota (the same way OpenMouse does it). Nothing here touches the network but `check`.
//

import Foundation

enum UpdateCheck {
  struct Release: Equatable, Identifiable {
    /// The tag as published, such as "v0.3.0".
    let version: String
    /// The release page.
    let pageURL: URL
    var id: String { version }
    /// "0.3.0", without the "v".
    var shortVersion: String { UpdateCheck.stripPrefix(version) }
  }

  enum Outcome: Equatable {
    case upToDate(current: String)
    case available(Release)
    case failed(String)
  }

  static let repository = "tarnish233/ohmyrime"
  static let requestTimeout: TimeInterval = 15
  /// Caps the whole response: a server that trickles bytes must not keep a check running forever.
  static let resourceTimeout: TimeInterval = 30

  /// Compares dotted numbers, ignoring a leading "v" and any suffix: "1.10.0" is newer than
  /// "1.9.9", which comparing the strings would get wrong. nil when a version cannot be read.
  static func isNewer(_ candidate: String, than current: String) -> Bool? {
    guard let lhs = versionParts(candidate), let rhs = versionParts(current) else { return nil }
    for index in 0..<max(lhs.count, rhs.count) {
      let left = index < lhs.count ? lhs[index] : 0
      let right = index < rhs.count ? rhs[index] : 0
      if left != right {
        return left > right
      }
    }
    return false
  }

  static func versionsMatch(_ lhs: String, _ rhs: String) -> Bool {
    guard let left = versionParts(lhs), let right = versionParts(rhs) else { return false }
    return (0..<max(left.count, right.count)).allSatisfy { index in
      (index < left.count ? left[index] : 0) == (index < right.count ? right[index] : 0)
    }
  }

  static func stripPrefix(_ version: String) -> String {
    var text = version.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.first == "v" || text.first == "V" {
      text.removeFirst()
    }
    return text
  }

  private static func versionParts(_ text: String) -> [UInt64]? {
    // "1.2.0-beta.3" compares as 1.2.0; empty or overflowing parts are refused, not skipped.
    let core = stripPrefix(text).prefix { $0.isNumber || $0 == "." }
    guard !core.isEmpty else { return nil }
    let components = core.split(separator: ".", omittingEmptySubsequences: false)
    guard !components.isEmpty else { return nil }
    var parts = [UInt64]()
    for component in components {
      guard !component.isEmpty, let value = UInt64(component) else { return nil }
      parts.append(value)
    }
    return parts
  }

  // MARK: URLs

  static func latestPageURL(repository: String = repository) -> URL? {
    guard let components = repositoryComponents(repository), let github = URL(string: "https://github.com") else { return nil }
    return github
      .appending(path: components.owner)
      .appending(path: components.name)
      .appending(path: "releases")
      .appending(path: "latest")
  }

  /// Where the assets are, for tests that must not download 30 MB from GitHub (a local folder).
  nonisolated(unsafe) static var assetBaseURL: URL?

  /// `releases/latest/download/…`: always the newest release's asset, so the name carries no version.
  static func assetURL(_ name: String, repository: String = repository) -> URL? {
    if let assetBaseURL {
      return assetBaseURL.appending(path: name)
    }
    guard let components = repositoryComponents(repository), let github = URL(string: "https://github.com") else { return nil }
    return github
      .appending(path: components.owner)
      .appending(path: components.name)
      .appending(path: "releases")
      .appending(path: "latest")
      .appending(path: "download")
      .appending(path: name)
  }

  /// The release a `releases/latest` redirect landed on: only from this repository's own GitHub
  /// URL, so that a proxy or a strange redirect cannot turn into an update.
  static func release(fromRedirect url: URL, repository: String = repository) -> Release? {
    guard let components = repositoryComponents(repository),
          url.scheme?.lowercased() == "https",
          url.host?.lowercased() == "github.com" else { return nil }
    let path = url.pathComponents.filter { $0 != "/" }
    guard path.count == 5,
          path[0].caseInsensitiveCompare(components.owner) == .orderedSame,
          path[1].caseInsensitiveCompare(components.name) == .orderedSame,
          path[2] == "releases",
          path[3] == "tag" else { return nil }
    let tag = path[4].removingPercentEncoding ?? path[4]
    guard !tag.isEmpty, versionParts(tag) != nil else { return nil }
    return Release(version: tag, pageURL: url)
  }

  private static func repositoryComponents(_ repository: String) -> (owner: String, name: String)? {
    let parts = repository.trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: "/", omittingEmptySubsequences: false)
      .map(String.init)
    guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
    return (parts[0], parts[1])
  }

  /// The SHA-256 in a `shasum -a 256` line: "711658…  ohmyrime.zip".
  static func parseChecksum(_ text: String) -> String? {
    guard let first = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first.map(String.init),
          first.count == 64, first.allSatisfy(\.isHexDigit) else { return nil }
    return first.lowercased()
  }

  static func sessionConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = requestTimeout
    configuration.timeoutIntervalForResource = resourceTimeout
    // Never a cached redirect or zip: an update must be what is published now.
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return configuration
  }

  // MARK: Checking

  static func check(currentVersion: String, repository: String = repository) async -> Outcome {
    guard let url = latestPageURL(repository: repository) else {
      return .failed("仓库地址无效")
    }
    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"
    request.timeoutInterval = requestTimeout
    request.setValue("text/html", forHTTPHeaderField: "Accept")
    request.setValue("ohmyrime/\(currentVersion)", forHTTPHeaderField: "User-Agent")

    let session = URLSession(configuration: sessionConfiguration())
    defer { session.invalidateAndCancel() }
    do {
      let (_, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        return .failed("没有收到服务器的回应")
      }
      switch http.statusCode {
      case 200:
        guard let finalURL = http.url, let release = self.release(fromRedirect: finalURL, repository: repository) else {
          return .failed("没能从 GitHub 的跳转里读出最新版本")
        }
        guard let newer = isNewer(release.version, than: currentVersion) else {
          return .failed("没法比较版本号（现在 \(currentVersion)，最新 \(release.version)）")
        }
        return newer ? .available(release) : .upToDate(current: currentVersion)
      case 404:
        return .failed("发布页不存在（404）")
      case 403, 429:
        return .failed("GitHub 暂时拒绝了请求（\(http.statusCode)），等一会儿再试")
      default:
        return .failed("服务器返回 \(http.statusCode)")
      }
    } catch {
      return .failed(Self.describe(error))
    }
  }

  /// Why a network error happened, in words.
  static func describe(_ error: Error) -> String {
    guard let error = error as? URLError else { return error.localizedDescription }
    switch error.code {
    case .notConnectedToInternet: return "没有网络"
    case .timedOut: return "连接 GitHub 超时"
    case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost: return "连不上 GitHub"
    default: return error.localizedDescription
    }
  }
}
