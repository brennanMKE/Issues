import Testing
import Foundation
@testable import Issues

#if os(macOS)

/// Pure validation-logic tests for `RemoteFolderPickerModel`. The SwiftUI
/// surface isn't unit-tested directly — these cover only the rules the
/// Continue buttons use to flip enabled/disabled.
struct RemoteFolderPickerStateTests {

    @Test func parsePortAcceptsLegalIntegers() {
        #expect(RemoteFolderPickerModel.parsePort("1") == 1)
        #expect(RemoteFolderPickerModel.parsePort("80") == 80)
        #expect(RemoteFolderPickerModel.parsePort("51823") == 51823)
        #expect(RemoteFolderPickerModel.parsePort("65535") == 65535)
    }

    @Test func parsePortTrimsWhitespace() {
        #expect(RemoteFolderPickerModel.parsePort("  443 ") == 443)
    }

    @Test func parsePortRejectsZeroAndOverflow() {
        #expect(RemoteFolderPickerModel.parsePort("0") == nil)
        #expect(RemoteFolderPickerModel.parsePort("65536") == nil)
        #expect(RemoteFolderPickerModel.parsePort("-1") == nil)
    }

    @Test func parsePortRejectsNonNumeric() {
        #expect(RemoteFolderPickerModel.parsePort("") == nil)
        #expect(RemoteFolderPickerModel.parsePort("eight") == nil)
        #expect(RemoteFolderPickerModel.parsePort("80a") == nil)
        #expect(RemoteFolderPickerModel.parsePort("443.0") == nil)
    }

    @Test func hostFieldsValidRequiresNonEmptyHost() {
        #expect(!RemoteFolderPickerModel.hostFieldsValid(hostText: "", portText: "51823"))
        #expect(!RemoteFolderPickerModel.hostFieldsValid(hostText: "   ", portText: "51823"))
    }

    @Test func hostFieldsValidRequiresValidPort() {
        #expect(!RemoteFolderPickerModel.hostFieldsValid(hostText: "100.74.12.5", portText: "0"))
        #expect(!RemoteFolderPickerModel.hostFieldsValid(hostText: "100.74.12.5", portText: "70000"))
        #expect(!RemoteFolderPickerModel.hostFieldsValid(hostText: "100.74.12.5", portText: ""))
    }

    @Test func hostFieldsValidAcceptsCommonInputs() {
        #expect(RemoteFolderPickerModel.hostFieldsValid(hostText: "100.74.12.5", portText: "51823"))
        #expect(RemoteFolderPickerModel.hostFieldsValid(hostText: "mac-mini.tail-scale.ts.net", portText: "443"))
        #expect(RemoteFolderPickerModel.hostFieldsValid(hostText: "fe80::abcd%en0", portText: "8000"))
    }

    @Test func tokenFieldValidRequiresIatPrefix() {
        #expect(!RemoteFolderPickerModel.tokenFieldValid(""))
        #expect(!RemoteFolderPickerModel.tokenFieldValid("abc123"))
        #expect(!RemoteFolderPickerModel.tokenFieldValid("bearer-foo"))
    }

    @Test func tokenFieldValidAcceptsIatPrefix() {
        #expect(RemoteFolderPickerModel.tokenFieldValid("iat_abc"))
        #expect(RemoteFolderPickerModel.tokenFieldValid("  iat_abc  "))
    }

    @Test func urlBuilderBracketsIpv6Literals() {
        let url = URLSessionRemoteHostProbe.url(host: "fe80::abcd", port: 51823, path: "/v1/host")
        #expect(url?.absoluteString == "http://[fe80::abcd]:51823/v1/host")
    }

    @Test func urlBuilderLeavesIpv4AndDnsAsIs() {
        let v4 = URLSessionRemoteHostProbe.url(host: "100.74.12.5", port: 51823, path: "/v1/host")
        #expect(v4?.absoluteString == "http://100.74.12.5:51823/v1/host")
        let dns = URLSessionRemoteHostProbe.url(host: "mac-mini.local", port: 80, path: "/v1/folders")
        #expect(dns?.absoluteString == "http://mac-mini.local:80/v1/folders")
    }

    @Test func urlBuilderRejectsEmptyHost() {
        #expect(URLSessionRemoteHostProbe.url(host: "", port: 51823, path: "/v1/host") == nil)
        #expect(URLSessionRemoteHostProbe.url(host: "   ", port: 51823, path: "/v1/host") == nil)
    }
}

#endif
