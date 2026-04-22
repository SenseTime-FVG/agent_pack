#!/usr/bin/env swift

import AppKit
import Foundation

final class ShortcutFriendlyTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleEditorShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class ShortcutFriendlySecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleEditorShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@discardableResult
private func handleEditorShortcut(_ event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard modifiers == [.command], let key = event.charactersIgnoringModifiers?.lowercased() else {
        return false
    }

    switch key {
    case "a":
        return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
    case "c":
        return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
    case "v":
        return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
    case "x":
        return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
    default:
        return false
    }
}

struct DefaultsRoot: Decodable {
    let llm_providers: [String: ProviderConfig]
}

struct ProviderConfig: Decodable {
    let name: String
    let base_url: String?
    let default_model: String?
    let signup_url: String?
}

struct ProviderChoice {
    let id: String
    let name: String
    let baseURL: String
    let defaultModel: String
    let signupURL: String
}

struct WizardResult: Encodable {
    let products: [String]
    let provider: String
    let base_url: String
    let model: String
    let api_key: String
}

enum VerificationOutcome {
    case proceed
    case editSettings
}

enum WizardError: Error {
    case canceled
    case invalidDefaults(String)
}

let installDir = "/usr/local/lib/agent-pack"
let defaultsPath =
    ProcessInfo.processInfo.environment["AGENTPACK_DEFAULTS_JSON"]
    ?? "\(installDir)/config/defaults.json"
let verifyCurlScriptPath =
    ProcessInfo.processInfo.environment["AGENTPACK_VERIFY_CURL_SCRIPT"]
    ?? "\(installDir)/shared/verify-llm-curl.sh"

func activateApp() {
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.activate(ignoringOtherApps: true)
}

func makeAlert(message: String, info: String = "") -> NSAlert {
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = info
    alert.alertStyle = .informational
    return alert
}

func runModal(_ alert: NSAlert, firstResponder: NSView? = nil) -> NSApplication.ModalResponse {
    activateApp()

    let window = alert.window
    if let firstResponder {
        window.initialFirstResponder = firstResponder
        DispatchQueue.main.async {
            window.makeFirstResponder(firstResponder)
            if let textField = firstResponder as? NSTextField {
                textField.selectText(nil)
            }
        }
    }

    return alert.runModal()
}

func runProductSelection() throws -> [String] {
    let alert = makeAlert(
        message: "选择要安装的 Agent",
        info: "请选择安装 Hermes Agent、OpenClaw，或同时安装两者。这个选择将决定 Agent Pack 后续实际安装的产品。"
    )
    alert.addButton(withTitle: "同时安装")
    alert.addButton(withTitle: "仅安装 Hermes")
    alert.addButton(withTitle: "仅安装 OpenClaw")
    alert.addButton(withTitle: "取消")

    switch runModal(alert) {
    case .alertFirstButtonReturn:
        return ["hermes", "openclaw"]
    case .alertSecondButtonReturn:
        return ["hermes"]
    case .alertThirdButtonReturn:
        return ["openclaw"]
    default:
        throw WizardError.canceled
    }
}

func runProviderSelection(providers: [ProviderChoice]) throws -> ProviderChoice {
    let alert = makeAlert(
        message: "选择 LLM 提供商",
        info: "安装成功后，Agent Pack 会将这里选择的 provider 配置自动写入 Hermes 和 OpenClaw。"
    )
    alert.addButton(withTitle: "继续")
    alert.addButton(withTitle: "取消")

    let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 28), pullsDown: false)
    popup.addItems(withTitles: providers.map(\.name))
    alert.accessoryView = popup

    let response = runModal(alert, firstResponder: popup)
    if response != .alertFirstButtonReturn {
        throw WizardError.canceled
    }

    return providers[popup.indexOfSelectedItem]
}

func runProviderSelection(providers: [ProviderChoice], selectedID: String) throws -> ProviderChoice {
    let alert = makeAlert(
        message: "选择 LLM 提供商",
        info: "安装成功后，Agent Pack 会将这里选择的 provider 配置自动写入 Hermes 和 OpenClaw。"
    )
    alert.addButton(withTitle: "继续")
    alert.addButton(withTitle: "取消")

    let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 28), pullsDown: false)
    popup.addItems(withTitles: providers.map(\.name))
    if let selectedIndex = providers.firstIndex(where: { $0.id == selectedID }) {
        popup.selectItem(at: selectedIndex)
    }
    alert.accessoryView = popup

    let response = runModal(alert, firstResponder: popup)
    if response != .alertFirstButtonReturn {
        throw WizardError.canceled
    }

    return providers[popup.indexOfSelectedItem]
}

func runTextInput(
    message: String,
    info: String,
    defaultValue: String = "",
    continueTitle: String = "继续",
    secure: Bool = false,
    required: Bool = false,
    trimWhitespace: Bool = true,
    removeInnerWhitespace: Bool = false
) throws -> String {
    while true {
        let alert = makeAlert(message: message, info: info)
        alert.addButton(withTitle: continueTitle)
        alert.addButton(withTitle: "取消")

        let fieldFrame = NSRect(x: 0, y: 0, width: 320, height: 26)
        let textField: NSTextField = secure
            ? ShortcutFriendlySecureTextField(frame: fieldFrame)
            : ShortcutFriendlyTextField(frame: fieldFrame)
        textField.stringValue = defaultValue
        textField.isEditable = true
        textField.isSelectable = true
        alert.accessoryView = textField

        let response = runModal(alert, firstResponder: textField)
        if response != .alertFirstButtonReturn {
            throw WizardError.canceled
        }

        var value = textField.stringValue
        if trimWhitespace {
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if removeInnerWhitespace {
            value = value.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        }

        if !required || !value.isEmpty {
            return value
        }

        let retry = makeAlert(
            message: "此项为必填项",
            info: "请输入内容后再继续。"
        )
        retry.addButton(withTitle: "重新输入")
        _ = runModal(retry)
    }
}

func runConfirmation(products: [String], providerName: String, model: String, baseURL: String?) throws {
    let productLabel: String
    switch products {
    case ["hermes", "openclaw"], ["openclaw", "hermes"]:
        productLabel = "Hermes Agent 和 OpenClaw"
    case ["hermes"]:
        productLabel = "Hermes Agent"
    case ["openclaw"]:
        productLabel = "OpenClaw"
    default:
        productLabel = "Agent Pack"
    }

    var info = "产品：\(productLabel)\n提供商：\(providerName)\n模型：\(model)\n\n安装可能需要几分钟，确认后会开始执行安装。"
    if let baseURL, !baseURL.isEmpty {
        info += "\nBase URL：\(baseURL)"
    }

    let alert = makeAlert(message: "准备开始安装", info: info)
    alert.addButton(withTitle: "开始安装")
    alert.addButton(withTitle: "取消")

    if runModal(alert) != .alertFirstButtonReturn {
        throw WizardError.canceled
    }
}

func runVerificationCommand(
    providerID: String,
    baseURL: String,
    model: String,
    apiKey: String
) -> (ok: Bool, output: String) {
    guard FileManager.default.isReadableFile(atPath: verifyCurlScriptPath) else {
        return (false, "Verification script not found at \(verifyCurlScriptPath)")
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [
        verifyCurlScriptPath,
        "--provider", providerID,
        "--api-key", apiKey,
        "--model", model,
        "--base-url", baseURL,
    ]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
    } catch {
        return (false, "Could not launch verification: \(error.localizedDescription)")
    }

    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return (process.terminationStatus == 0, output.isEmpty ? "(no output captured)" : output)
}

func runVerificationStep(
    providerID: String,
    providerName: String,
    baseURL: String,
    model: String,
    apiKey: String
) throws -> VerificationOutcome {
    if apiKey.isEmpty {
        return .proceed
    }

    while true {
        let prompt = makeAlert(
            message: "验证连接",
            info: "在正式安装前，Agent Pack 可以先用模型 \(model) 测试一下你的 \(providerName) 配置是否可用。"
        )
        prompt.addButton(withTitle: "立即验证")
        prompt.addButton(withTitle: "跳过")
        prompt.addButton(withTitle: "取消")

        switch runModal(prompt) {
        case .alertFirstButtonReturn:
            let result = runVerificationCommand(
                providerID: providerID,
                baseURL: baseURL,
                model: model,
                apiKey: apiKey
            )
            if result.ok {
                let success = makeAlert(
                    message: "连接验证成功",
                    info: result.output
                )
                success.addButton(withTitle: "继续")
                _ = runModal(success)
                return .proceed
            }

            let failure = makeAlert(
                message: "验证失败",
                info: result.output + "\n\n你可以返回修改设置、仍然继续安装，或者取消本次安装。"
            )
            failure.alertStyle = .warning
            failure.addButton(withTitle: "修改设置")
            failure.addButton(withTitle: "仍然继续")
            failure.addButton(withTitle: "取消")
            let failureResponse = runModal(failure)
            if failureResponse == .alertFirstButtonReturn {
                return .editSettings
            }
            if failureResponse == .alertSecondButtonReturn {
                return .proceed
            }
            throw WizardError.canceled
        case .alertSecondButtonReturn:
            return .proceed
        default:
            throw WizardError.canceled
        }
    }
}

func loadProviders() throws -> [ProviderChoice] {
    let data = try Data(contentsOf: URL(fileURLWithPath: defaultsPath))
    let root = try JSONDecoder().decode(DefaultsRoot.self, from: data)
    let order = ["openrouter", "openai", "anthropic", "custom"]

    return try order.map { key in
        guard let config = root.llm_providers[key] else {
            throw WizardError.invalidDefaults("Missing provider config for \(key)")
        }
        return ProviderChoice(
            id: key,
            name: config.name,
            baseURL: config.base_url ?? "",
            defaultModel: config.default_model ?? "",
            signupURL: config.signup_url ?? ""
        )
    }
}

do {
    let providers = try loadProviders()
    let products = try runProductSelection()
    var selectedProviderID = providers.first?.id ?? "openrouter"
    var lastCustomBaseURL = ""
    var lastCustomModel = ""
    var lastApiKey = ""
    var selectedProvider: ProviderChoice?
    var selectedBaseURL = ""
    var selectedModel = ""
    var selectedApiKey = ""

    while true {
        let provider = try runProviderSelection(providers: providers, selectedID: selectedProviderID)
        selectedProviderID = provider.id

        let baseURL: String
        if provider.id == "custom" {
            baseURL = try runTextInput(
                message: "自定义 Base URL",
                info: "请输入你的 OpenAI 兼容接口的 Base URL。",
                defaultValue: lastCustomBaseURL,
                required: true
            )
            lastCustomBaseURL = baseURL
        } else {
            baseURL = provider.baseURL
        }

        let model: String
        if provider.id == "custom" {
            model = try runTextInput(
                message: "自定义模型名称",
                info: "请输入你的自定义接口对应的模型 ID。",
                defaultValue: lastCustomModel,
                required: true,
                removeInnerWhitespace: true
            )
            lastCustomModel = model
        } else {
            let enteredModel = try runTextInput(
                message: "模型 ID",
                info: "你可以保留默认模型，也可以改成该 provider 支持的任意模型 ID。",
                defaultValue: provider.defaultModel
            )
            model = enteredModel.isEmpty ? provider.defaultModel : enteredModel
        }

        let keyInfo: String
        if provider.signupURL.isEmpty {
            keyInfo = "请输入你的 API key。如果暂时不想配置 LLM，也可以留空直接跳过。"
        } else {
            keyInfo = "请输入你的 API key。留空则跳过本次配置。\n\n注册链接：\n\(provider.signupURL)"
        }
        let apiKey = try runTextInput(
            message: "API Key",
            info: keyInfo,
            defaultValue: lastApiKey,
            continueTitle: "继续",
            secure: true
        )
        lastApiKey = apiKey

        let verificationOutcome = try runVerificationStep(
            providerID: provider.id,
            providerName: provider.name,
            baseURL: baseURL,
            model: model,
            apiKey: apiKey
        )
        if verificationOutcome == .editSettings {
            continue
        }

        selectedProvider = provider
        selectedBaseURL = baseURL
        selectedModel = model
        selectedApiKey = apiKey
        break
    }

    guard let provider = selectedProvider else {
        throw WizardError.invalidDefaults("No provider selected")
    }

    try runConfirmation(
        products: products,
        providerName: provider.name,
        model: selectedModel,
        baseURL: provider.id == "custom" ? selectedBaseURL : nil
    )

    let payload = WizardResult(
        products: products,
        provider: provider.id,
        base_url: selectedBaseURL,
        model: selectedModel,
        api_key: selectedApiKey
    )
    let jsonData = try JSONEncoder().encode(payload)
    FileHandle.standardOutput.write(jsonData)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch WizardError.canceled {
    Foundation.exit(128)
    } catch {
        let alert = makeAlert(
            message: "Agent Pack 安装向导启动失败",
            info: error.localizedDescription
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        _ = runModal(alert)
        fputs("[agent-pack] GUI wizard failed: \(error)\n", stderr)
        Foundation.exit(1)
}
