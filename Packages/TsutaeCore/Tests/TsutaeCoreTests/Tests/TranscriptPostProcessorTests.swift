import Foundation
import XCTest
@testable import TsutaeCore

final class TranscriptPostProcessorTests: XCTestCase {
    private static let ruleEvalCases: [RuleEvalCase] = [
        .init(
            id: "zh_filler_product_terms",
            category: "dictionary",
            raw: "呃我们今天先把 code x 的 hook 通知测一下然后那个 kanade 的 token 我已经配好了但是 github issue 那个入口还没确认",
            expected: "我们今天先把 Codex 的 hook 通知测一下然后那个 Kanade 的 token 我已经配好了但是 GitHub Issue 那个入口还没确认。"
        ),
        .init(
            id: "zh_question_api_latency",
            category: "punctuation",
            raw: "done 17ms 走 api 了吗",
            expected: "done 17ms 走 API 了吗？"
        ),
        .init(
            id: "zh_binary_question",
            category: "punctuation",
            raw: "这个是不是走 remote 了",
            expected: "这个是不是走 remote 了？"
        ),
        .init(
            id: "zh_exclamation_warning",
            category: "punctuation",
            raw: "注意不要覆盖用户配置",
            expected: "注意不要覆盖用户配置！"
        ),
        .init(
            id: "zh_spoken_punctuation_commands",
            category: "spokenPunctuation",
            raw: "先跑 just build 逗号再跑 just test core 句号",
            expected: "先跑 just build，再跑 just test core。"
        ),
        .init(
            id: "zh_spoken_question_command",
            category: "spokenPunctuation",
            raw: "这个接口走 remote 问号",
            expected: "这个接口走 remote？"
        ),
        .init(
            id: "zh_spoken_newline_command",
            category: "spokenPunctuation",
            raw: "第一点补 readme 换行 第二点补 server api 文档",
            expected: "第一点补 README\n第二点补 Server API 文档。"
        ),
        .init(
            id: "en_filler_question",
            category: "filler",
            raw: "uh can we ship the readme update today",
            expected: "can we ship the README update today?"
        ),
        .init(
            id: "en_filler_statement",
            category: "filler",
            raw: "um let's wire the server api token first",
            expected: "let's wire the Server API token first."
        ),
        .init(
            id: "en_spoken_punctuation_commands",
            category: "spokenPunctuation",
            raw: "please update the readme comma then run tests period",
            expected: "please update the README, then run tests."
        ),
        .init(
            id: "en_spoken_question_command",
            category: "spokenPunctuation",
            raw: "can we ship this question mark",
            expected: "can we ship this?"
        ),
        .init(
            id: "en_spoken_new_paragraph_command",
            category: "spokenPunctuation",
            raw: "write summary new paragraph add action items",
            expected: "write summary\n\nadd action items."
        ),
        .init(
            id: "mixed_openai_base_url",
            category: "dictionary",
            raw: "open ai compatible base url 要配置到 local host",
            expected: "OpenAI-compatible Base URL 要配置到 localhost。"
        ),
        .init(
            id: "existing_question_punctuation",
            category: "punctuation",
            raw: "这个可以吗？",
            expected: "这个可以吗？"
        ),
        .init(
            id: "existing_english_punctuation",
            category: "punctuation",
            raw: "ship it!",
            expected: "ship it!"
        ),
        .init(
            id: "cjk_spacing",
            category: "spacing",
            raw: "嗯啊啊tts 和 stt 的 ui 先统一",
            expected: "TTS 和 STT 的 UI 先统一。"
        ),
        .init(
            id: "zh_single_filler_at_start",
            category: "filler",
            raw: "啊 这个我们先不做",
            expected: "这个我们先不做。"
        ),
        .init(
            id: "zh_preserve_particle",
            category: "guardrail",
            raw: "好啊我们周五见",
            expected: "好啊我们周五见。"
        ),
        .init(
            id: "zh_duplicate_then",
            category: "repetition",
            raw: "然后然后我们先跑测试",
            expected: "然后我们先跑测试。"
        ),
        .init(
            id: "zh_duplicate_that",
            category: "repetition",
            raw: "那个那个先看日志",
            expected: "那个先看日志。"
        ),
        .init(
            id: "zh_self_correction_not_right_actually",
            category: "selfCorrection",
            raw: "我们周四见等等不对其实周五三点见",
            expected: "周五三点见。"
        ),
        .init(
            id: "zh_question_why",
            category: "punctuation",
            raw: "为什么 notification 没弹出来",
            expected: "为什么 notification 没弹出来？"
        ),
        .init(
            id: "zh_question_has_or_not",
            category: "punctuation",
            raw: "有没有可能是配置问题",
            expected: "有没有可能是配置问题？"
        ),
        .init(
            id: "zh_exclamation_too_slow",
            category: "punctuation",
            raw: "太慢了",
            expected: "太慢了！"
        ),
        .init(
            id: "zh_plain_statement",
            category: "punctuation",
            raw: "周五三点见",
            expected: "周五三点见。"
        ),
        .init(
            id: "term_git_hub_issue",
            category: "dictionary",
            raw: "git hub issue 入口还没确认",
            expected: "GitHub Issue 入口还没确认。"
        ),
        .init(
            id: "term_typescript_swiftui",
            category: "dictionary",
            raw: "type script 和 swift ui 的 case 也加一下",
            expected: "TypeScript 和 SwiftUI 的 case 也加一下。"
        ),
        .init(
            id: "term_swift_package_manager",
            category: "dictionary",
            raw: "swift package manager 的 test 要快",
            expected: "Swift Package Manager 的 test 要快。"
        ),
        .init(
            id: "term_xcode",
            category: "dictionary",
            raw: "x code build 已经过了",
            expected: "Xcode build 已经过了。"
        ),
        .init(
            id: "term_deepseek_mimo",
            category: "dictionary",
            raw: "deep seek flash 比 mimo 快吗",
            expected: "DeepSeek flash 比 Mimo 快吗？"
        ),
        .init(
            id: "term_keychain",
            category: "dictionary",
            raw: "key chain 权限弹窗消失了",
            expected: "Keychain 权限弹窗消失了。"
        ),
        .init(
            id: "term_server_token",
            category: "dictionary",
            raw: "server token 已经配置好了",
            expected: "Server token 已经配置好了。"
        ),
        .init(
            id: "term_voice_id",
            category: "dictionary",
            raw: "remote 的 voice id 不应该被覆盖",
            expected: "remote 的 voiceId 不应该被覆盖。"
        ),
        .init(
            id: "term_github_actions_json_yaml",
            category: "dictionary",
            raw: "git hub actions 读取 json 和 yaml 配置",
            expected: "GitHub Actions 读取 JSON 和 YAML 配置。"
        ),
        .init(
            id: "term_url_https_macos_ios",
            category: "dictionary",
            raw: "mac os 和 ios 上的 https url 需要保留",
            expected: "macOS 和 iOS 上的 HTTPS URL 需要保留。"
        ),
        .init(
            id: "term_api_key",
            category: "dictionary",
            raw: "the api key is in key chain",
            expected: "the API key is in Keychain."
        ),
        .init(
            id: "term_llm_readme",
            category: "dictionary",
            raw: "llm 最后整理这个 readme",
            expected: "LLM 最后整理这个 README。"
        ),
        .init(
            id: "term_asr_tts",
            category: "dictionary",
            raw: "asr 输出 tts 胶囊",
            expected: "ASR 输出 TTS 胶囊。"
        ),
        .init(
            id: "artifact_paraformer_bpe_markers",
            category: "artifact",
            raw: "看一下 c@@ase 和 tr@@an@@sc@@ri@@p@@t 流程",
            expected: "看一下 case 和 transcript 流程。"
        ),
        .init(
            id: "artifact_paraformer_transscribe",
            category: "artifact",
            raw: "这个 tr@@ans@@sc@@ri@@be 怎么优化",
            expected: "这个 transcribe 怎么优化。"
        ),
        .init(
            id: "artifact_paraformer_ssd_spacing",
            category: "artifact",
            raw: "影响ss@@d的说明吗",
            expected: "影响 SSD 的说明吗？"
        ),
        .init(
            id: "artifact_paraformer_ui_spacing",
            category: "artifact",
            raw: "目前u@@i和ser@@ver都是独立启动的吗",
            expected: "目前 UI 和 server 都是独立启动的吗？"
        ),
        .init(
            id: "artifact_paraformer_codex_app",
            category: "artifact",
            raw: "这个是con@@de@@xap@@p写的还是co@@i写的",
            expected: "这个是 Codex app 写的还是 coi 写的。"
        ),
        .init(
            id: "real_asr_phonetic_codex_hook",
            category: "dictionary",
            raw: "扣得克斯 的 hook 通知收到了",
            expected: "Codex 的 hook 通知收到了。"
        ),
        .init(
            id: "real_asr_phonetic_tsutae_server_token",
            category: "dictionary",
            raw: "次他诶 server token 已经配置好了",
            expected: "Tsutae Server token 已经配置好了。"
        ),
        .init(
            id: "real_asr_remote_api_fallback_artifacts",
            category: "artifact",
            raw: "tts部分目前只调通了re@@mo@@teapi跟app@@le的fu@@llback",
            expected: "TTS 部分目前只调通了 Remote API 跟 Apple 的 fallback。"
        ),
        .init(
            id: "artifact_paraformer_scope_type",
            category: "artifact",
            raw: "ty@@pe是不是改成s@@co@@pety@@pe然后从enjoypro@@mo@@tion的s@@co@@pety@@pe赋一下值",
            expected: "type 是不是改成 scopeType 然后从 enjoypromotion 的 scopeType 赋一下值？"
        ),
        .init(
            id: "guardrail_amount_not_filler",
            category: "guardrail",
            raw: "减免金额上跟老版本v二应该是一样的",
            expected: "减免金额上跟老版本 v 二应该是一样的。"
        ),
        .init(
            id: "guardrail_amount_question_not_filler",
            category: "guardrail",
            raw: "我们还需要再看一下分摊因为金额是非零然后见面以后会有分摊问题吗",
            expected: "我们还需要再看一下分摊因为金额是非零然后见面以后会有分摊问题吗？"
        ),
        .init(
            id: "en_question_where",
            category: "punctuation",
            raw: "where is the token config",
            expected: "where is the token config?"
        ),
        .init(
            id: "en_exclamation_great",
            category: "punctuation",
            raw: "great ship it",
            expected: "great ship it!"
        ),
        .init(
            id: "guardrail_self_correction_kept_for_llm",
            category: "guardrail",
            raw: "不是 minimal 是 standard 这个交给 llm 修",
            expected: "不是 minimal 是 standard 这个交给 LLM 修。"
        ),
        .init(
            id: "guardrail_codec_not_codex",
            category: "guardrail",
            raw: "codec internals 不应该变成 codex",
            expected: "codec internals 不应该变成 Codex。"
        )
    ]

    private static let remoteEvalCases: [RemoteEvalCase] = [
        .init(
            id: "remote_clean_self_correction",
            task: .cleanDictation,
            raw: "呃我们周四见等等不对其实周五三点见然后把 codex hook 的通知也测一下",
            remoteOutput: "我们周五三点见，然后把 Codex hook 的通知也测一下。",
            criteria: .init(
                mustContain: ["周五三点", "Codex hook", "通知"],
                mustNotContain: ["呃", "周四", "等等不对"]
            )
        ),
        .init(
            id: "remote_rewrite_message",
            task: .rewriteMessage,
            raw: "嗯帮我写一下就是说我们已经把 server token 和 hook 分应用配置做好了然后下周想重点看一下 llm 整理文案和会议纪要这个能力",
            remoteOutput: "我们已经完成 Server token 和 hook 的按应用配置。下周重点验证 LLM 文案整理和会议纪要能力。",
            criteria: .init(
                mustContain: ["Server token", "hook", "LLM", "会议纪要"],
                mustNotContain: ["嗯", "就是说"],
                maxLength: 120
            )
        ),
        .init(
            id: "remote_meeting_notes",
            task: .meetingNotes,
            raw: "今天会议说 tsutae 发布准备 文档要补 readme 和 server api stt 长录音先提示分段 下周一我整理测试 case kanade 接 server token",
            remoteOutput: """
            ## 摘要
            - Tsutae 发布准备需要补文档和处理 STT 长录音提示。

            ## 行动项
            - 未指定：补 README 和 Server API 文档。
            - 我：下周一前整理测试 case。
            - Kanade：接入 server token。

            ## 决策
            - STT 长录音先提示用户分段。
            """,
            criteria: .init(
                mustContain: ["##", "## 行动项", "STT", "README", "Server API", "Kanade", "未指定"],
                mustNotContain: ["呃", "嗯", "[Tsutae]", "Server API STT", "## 开放问题\n", "Tsutae：", "**Tsutae**"],
                maxLength: 320
            )
        ),
        .init(
            id: "remote_clean_spoken_punctuation_and_terms",
            task: .cleanDictation,
            raw: "请打开 git hub actions 逗号看一下 json 配置有没有错 问号",
            remoteOutput: "请打开 GitHub Actions，看一下 JSON 配置有没有错？",
            criteria: .init(
                mustContain: ["GitHub Actions", "JSON", "？"],
                mustNotContain: ["git hub", "逗号", "问号"]
            )
        ),
        .init(
            id: "remote_rewrite_issue_comment",
            task: .rewriteMessage,
            raw: "嗯帮我整理成 github issue 评论 就是 tts 从 local 切回 remote 以后 voice id 不应该被 kokoro 的 voice 覆盖 这个需要记录每个 provider 上一次选择",
            remoteOutput: "TTS 从 local 切回 remote 后，remote voiceId 不应该被 Kokoro 的 voice 覆盖。需要按 provider 记录上一次选择，避免切换时丢配置。",
            criteria: .init(
                mustContain: ["TTS", "remote", "voiceId", "provider"],
                mustNotContain: ["嗯", "就是"],
                maxLength: 140
            )
        ),
        .init(
            id: "remote_rewrite_english_technical_message",
            task: .rewriteMessage,
            raw: "uh can you note that github actions should run the swift package manager tests and update the readme for the server api",
            remoteOutput: "GitHub Actions should run the Swift Package Manager tests, and the README should document the Server API.",
            criteria: .init(
                mustContain: ["GitHub Actions", "Swift Package Manager", "README", "Server API"],
                mustNotContain: ["uh"],
                maxLength: 140
            )
        ),
        .init(
            id: "remote_meeting_notes_open_question",
            task: .meetingNotes,
            raw: "今天讨论 post processing 默认先走 rules remote 只在手动整理时触发 决策是先不上自动 remote 开放问题是长文本什么时候自动触发还没确定",
            remoteOutput: """
            ## 摘要
            - Post processing 默认先走 rules，remote 只在手动整理时触发。

            ## 决策
            - 暂不上自动 remote。

            ## 开放问题
            - 长文本什么时候自动触发还没确定。
            """,
            criteria: .init(
                mustContain: ["## 摘要", "## 决策", "## 开放问题", "自动触发"],
                mustNotContain: ["未指定："],
                maxLength: 360
            )
        ),
        .init(
            id: "remote_meeting_notes_unassigned_action",
            task: .meetingNotes,
            raw: "会议说发布前需要补 readme 和 server api 参数说明 还要跑一遍 remote eval 没有说谁负责",
            remoteOutput: """
            ## 摘要
            - 发布前需要补 README 和 Server API 参数说明，并跑一遍 remote eval。

            ## 行动项
            - 未指定：补 README 和 Server API 参数说明。
            - 未指定：跑一遍 remote eval。
            """,
            criteria: .init(
                mustContain: ["## 行动项", "- 未指定：", "README", "Server API", "remote eval"],
                mustNotContain: ["我：", "Kanade：", "Codex：", "## 开放问题"],
                maxLength: 260
            )
        )
    ]

    func testRuleCleanerRemovesFillersAndAddsChinesePunctuation() {
        let raw = " 呃嗯啊啊我们 周五 三点见 然后 测一下 "

        let cleaned = RuleBasedTranscriptCleaner.clean(raw)

        XCTAssertEqual(cleaned, "我们周五三点见然后测一下。")
    }

    func testRuleCleanerKeepsNonFillerChineseParticle() {
        let raw = "好啊我们周五见"

        let cleaned = RuleBasedTranscriptCleaner.clean(raw)

        XCTAssertEqual(cleaned, "好啊我们周五见。")
    }

    func testRuleCleanerKeepsAmountCharacters() {
        XCTAssertEqual(RuleBasedTranscriptCleaner.clean("金额是非零"), "金额是非零。")
        XCTAssertEqual(RuleBasedTranscriptCleaner.clean("余额和额度都要保留"), "余额和额度都要保留。")
    }

    func testRuleCleanerRemovesStandaloneEFillersOnly() {
        XCTAssertEqual(RuleBasedTranscriptCleaner.clean("额 我们先看日志"), "我们先看日志。")
        XCTAssertEqual(RuleBasedTranscriptCleaner.clean("金额 额 还要分摊"), "金额还要分摊。")
    }

    func testRuleCleanerRemovesEnglishFillersAndAddsPunctuation() {
        let raw = "um let's ship this today uh"

        let cleaned = RuleBasedTranscriptCleaner.clean(raw)

        XCTAssertEqual(cleaned, "let's ship this today.")
    }

    func testRuleCleanerAddsChineseQuestionMarkForShortQuestions() {
        XCTAssertEqual(RuleBasedTranscriptCleaner.clean("这个是不是走 API 了"), "这个是不是走 API 了？")
        XCTAssertEqual(RuleBasedTranscriptCleaner.clean("怎么回事"), "怎么回事？")
    }

    func testRuleCleanerAddsChineseExclamationMarkConservatively() {
        XCTAssertEqual(RuleBasedTranscriptCleaner.clean("太快了"), "太快了！")
        XCTAssertEqual(RuleBasedTranscriptCleaner.clean("注意不要覆盖用户配置"), "注意不要覆盖用户配置！")
    }

    func testRuleCleanerAddsEnglishQuestionMarkForShortQuestions() {
        XCTAssertEqual(RuleBasedTranscriptCleaner.clean("can we ship this today"), "can we ship this today?")
        XCTAssertEqual(RuleBasedTranscriptCleaner.clean("why is remote slow"), "why is remote slow?")
    }

    func testRuleCleanerDoesNotDuplicateTerminalPunctuation() {
        XCTAssertEqual(RuleBasedTranscriptCleaner.clean("这个可以吗？"), "这个可以吗？")
        XCTAssertEqual(RuleBasedTranscriptCleaner.clean("ship it!"), "ship it!")
    }

    func testRuleCleanerNormalizesSpokenPunctuationCommands() {
        XCTAssertEqual(
            RuleBasedTranscriptCleaner.clean("先跑测试逗号再看日志句号"),
            "先跑测试，再看日志。"
        )
        XCTAssertEqual(
            RuleBasedTranscriptCleaner.clean("write summary new paragraph add action items"),
            "write summary\n\nadd action items."
        )
    }

    func testOpenAICompatibleTextClientSendsChatCompletionRequest() async throws {
        let session = MockTextURLSession(
            data: Data(#"{"choices":[{"message":{"content":"Clean output."}}]}"#.utf8),
            statusCode: 200
        )
        let client = OpenAICompatibleTextClient(
            baseURL: URL(string: "https://example.com/v1")!,
            model: "test-model",
            apiKey: "test-key",
            session: session
        )

        let output = try await client.rewriteTranscript("raw output", task: .cleanDictation, language: "en")

        XCTAssertEqual(output, "Clean output.")
        let request = try XCTUnwrap(session.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertTrue(body.containsASCII("\"model\":\"test-model\""))
        XCTAssertTrue(body.containsASCII("raw output"))
        XCTAssertTrue(body.containsASCII("Language hint: en"))
    }

    func testDictionaryAppliesBuiltInTermsWithBoundaries() {
        let result = TranscriptDictionaryReplacer.apply(
            to: "code x hook for kanade and github issue, not codec internals",
            config: .init(enabled: true, useBuiltIn: true)
        )

        XCTAssertEqual(result.text, "Codex hook for Kanade and GitHub Issue, not codec internals")
        XCTAssertEqual(result.matches, ["github issue", "code x", "kanade"])
    }

    func testDictionaryAppliesAutomaticContextTerms() {
        let context = TranscriptDictionaryContext(terms: ["Linear", "MyCustomApp"])

        let result = TranscriptDictionaryReplacer.apply(
            to: "linear sent this from my custom app",
            config: .init(enabled: true, useBuiltIn: false, useAutomatic: true),
            context: context
        )

        XCTAssertEqual(result.text, "Linear sent this from MyCustomApp")
        XCTAssertEqual(result.matches, ["My Custom App", "Linear"])
    }

    func testDictionaryCustomEntriesOverrideAutomaticTerms() {
        let context = TranscriptDictionaryContext(terms: ["Linear"])

        let result = TranscriptDictionaryReplacer.apply(
            to: "linear issue",
            config: .init(
                enabled: true,
                useBuiltIn: false,
                useAutomatic: true,
                entries: [.init(key: "linear", value: "Linear Workspace")]
            ),
            context: context
        )

        XCTAssertEqual(result.text, "Linear Workspace issue")
        XCTAssertEqual(result.matches, ["linear"])
    }

    func testDictionaryCanDisableAutomaticContextTerms() {
        let context = TranscriptDictionaryContext(terms: ["Linear"])

        let result = TranscriptDictionaryReplacer.apply(
            to: "linear issue",
            config: .init(enabled: true, useBuiltIn: false, useAutomatic: false),
            context: context
        )

        XCTAssertEqual(result.text, "linear issue")
        XCTAssertEqual(result.matches, [])
    }

    func testRulesModeAppliesDictionaryAfterCleaning() async throws {
        let config = Config.TranscriptPostProcessingConfig(
            enabled: true,
            mode: .rules,
            dictionary: .init(enabled: true, useBuiltIn: true)
        )

        let result = try await TranscriptPostProcessor.process(
            "呃 code x 和 卡纳德 今天测 github issue",
            config: config
        )

        XCTAssertEqual(result.processedText, "Codex 和 Kanade 今天测 GitHub Issue。")
        XCTAssertEqual(result.provider, "rules+dictionary")
        XCTAssertEqual(result.dictionaryMatches, ["github issue", "code x", "卡纳德"])
    }

    func testSmartModeUsesRulesForCleanDictation() async throws {
        let session = MockTextURLSession(
            data: mockChatResponse("should not be used"),
            statusCode: 200
        )
        let config = Config.TranscriptPostProcessingConfig(
            enabled: true,
            mode: .smart,
            defaultTask: .cleanDictation,
            remote: .init(enabled: true, baseURL: "https://example.com", model: "smart-model"),
            dictionary: .init(enabled: true, useBuiltIn: true)
        )

        let result = try await TranscriptPostProcessor.process(
            "呃 code x hook 测一下",
            config: config,
            session: session
        )

        XCTAssertEqual(result.mode, .smart)
        XCTAssertEqual(result.provider, "smart:rules+dictionary")
        XCTAssertEqual(result.processedText, "Codex hook 测一下。")
        XCTAssertNil(session.lastRequest)
    }

    func testSmartModeUsesRemoteForRewriteTasksWhenConfigured() async throws {
        let session = MockTextURLSession(
            data: mockChatResponse("我们已完成 Server token 配置。"),
            statusCode: 200
        )
        let config = Config.TranscriptPostProcessingConfig(
            enabled: true,
            mode: .smart,
            defaultTask: .rewriteMessage,
            remote: .init(enabled: true, baseURL: "https://example.com", model: "smart-model"),
            dictionary: .init(enabled: true, useBuiltIn: true)
        )

        let result = try await TranscriptPostProcessor.process(
            "嗯我们已经把 server token 配好了",
            config: config,
            session: session
        )

        XCTAssertEqual(result.mode, .smart)
        XCTAssertEqual(result.provider, "smart:openai_compatible+dictionary")
        XCTAssertEqual(result.model, "smart-model")
        XCTAssertEqual(result.processedText, "我们已完成 Server token 配置。")
        XCTAssertEqual(session.lastRequest?.url?.absoluteString, "https://example.com/v1/chat/completions")
    }

    func testSmartModeFallsBackToRulesWhenRemoteIsIncomplete() async throws {
        let config = Config.TranscriptPostProcessingConfig(
            enabled: true,
            mode: .smart,
            defaultTask: .meetingNotes,
            remote: .init(enabled: true, baseURL: nil, model: nil),
            dictionary: .init(enabled: true, useBuiltIn: true)
        )

        let result = try await TranscriptPostProcessor.process(
            "readme 和 server api 要补",
            config: config
        )

        XCTAssertEqual(result.mode, .smart)
        XCTAssertEqual(result.provider, "smart:rules+dictionary")
        XCTAssertEqual(result.processedText, "README 和 Server API 要补。")
    }

    func testRuleEvalSuiteQuality() async throws {
        let config = Config.TranscriptPostProcessingConfig(
            enabled: true,
            mode: .rules,
            dictionary: .init(enabled: true, useBuiltIn: true)
        )

        var report = EvalReport()
        var records: [LocalEvalRecord] = []
        for testCase in Self.ruleEvalCases {
            let startedAt = CFAbsoluteTimeGetCurrent()
            let result = try await TranscriptPostProcessor.process(testCase.raw, config: config)
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            let failures = TranscriptEval.evaluate(
                output: result.processedText,
                criteria: .init(exact: testCase.expected)
            )
            records.append(LocalEvalRecord(
                id: testCase.id,
                category: testCase.category,
                raw: testCase.raw,
                expected: testCase.expected,
                output: result.processedText,
                elapsedMs: elapsedMs,
                passed: failures.isEmpty,
                failures: failures,
                provider: result.provider,
                dictionaryMatches: result.dictionaryMatches
            ))

            report.record(caseID: testCase.id, category: testCase.category, failures: failures)
            XCTAssertTrue(failures.isEmpty, "\(testCase.id): \(failures.joined(separator: "; "))")
        }
        print(report.summary(label: "Transcript rule eval quality"))
        if let resultPath = ProcessInfo.processInfo.environment["TSUTAE_LOCAL_EVAL_RESULTS"]?.blankToNil {
            try Self.writeJSONLRecords(records, to: URL(fileURLWithPath: resultPath))
        }
    }

    func testRuleEvalSuiteLatencyBudget() async throws {
        let config = Config.TranscriptPostProcessingConfig(
            enabled: true,
            mode: .rules,
            dictionary: .init(enabled: true, useBuiltIn: true)
        )
        let rounds = 25
        let directStartedAt = CFAbsoluteTimeGetCurrent()

        for _ in 0..<rounds {
            for testCase in Self.ruleEvalCases {
                _ = TranscriptDictionaryReplacer.apply(
                    to: RuleBasedTranscriptCleaner.clean(testCase.raw),
                    config: config.dictionary
                )
            }
        }

        let directElapsedMs = (CFAbsoluteTimeGetCurrent() - directStartedAt) * 1000
        let directAverageMs = directElapsedMs / Double(rounds * Self.ruleEvalCases.count)
        let startedAt = CFAbsoluteTimeGetCurrent()

        for _ in 0..<rounds {
            for testCase in Self.ruleEvalCases {
                _ = try await TranscriptPostProcessor.process(testCase.raw, config: config)
            }
        }

        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        let averageMs = elapsedMs / Double(rounds * Self.ruleEvalCases.count)
        print(String(format: "Transcript rule eval: %d cases, %.3f ms/case direct, %.3f ms/case processor", Self.ruleEvalCases.count, directAverageMs, averageMs))
        XCTAssertLessThan(directAverageMs, 5)
        XCTAssertLessThan(averageMs, 20)
    }

    func testRemoteEvalSuiteSemanticCriteria() async throws {
        var report = EvalReport()
        for testCase in Self.remoteEvalCases {
            let session = MockTextURLSession(
                data: mockChatResponse(testCase.remoteOutput),
                statusCode: 200
            )
            let config = Config.TranscriptPostProcessingConfig(
                enabled: true,
                mode: .remote,
                defaultTask: testCase.task,
                remote: .init(
                    enabled: true,
                    baseURL: "https://example.com/v1",
                    model: "eval-model",
                    apiKeyRef: nil
                )
            )

            let result = try await TranscriptPostProcessor.process(
                testCase.raw,
                config: config,
                session: session
            )
            let failures = TranscriptEval.evaluate(output: result.processedText, criteria: testCase.criteria)

            report.record(caseID: testCase.id, category: testCase.task.rawValue, failures: failures)
            XCTAssertEqual(result.task, testCase.task)
            XCTAssertTrue(failures.isEmpty, "\(testCase.id): \(failures.joined(separator: "; "))")
            let body = try XCTUnwrap(session.lastRequest?.httpBody)
            switch testCase.task {
            case .cleanDictation:
                XCTAssertTrue(body.containsASCII("Clean this dictated transcript:"), testCase.id)
            case .rewriteMessage:
                XCTAssertTrue(body.containsASCII("Rewrite this dictated note into a ready-to-send message:"), testCase.id)
            case .meetingNotes:
                XCTAssertTrue(body.containsASCII("Create meeting notes from this transcript:"), testCase.id)
            }
        }
        print(report.summary(label: "Transcript remote eval semantic criteria"))
    }

    func testRemoteEvalSuiteAgainstConfiguredProvider() async throws {
        guard ProcessInfo.processInfo.environment["TSUTAE_RUN_REMOTE_EVAL"] == "1" else {
            throw XCTSkip("Set TSUTAE_RUN_REMOTE_EVAL=1 to call the configured remote text model.")
        }

        let config = try Self.loadRemoteEvalConfig()
        guard config.postProcessing.remote.enabled else {
            XCTFail("postProcessing.remote.enabled must be true for remote eval.")
            return
        }
        guard config.postProcessing.remote.baseURL?.blankToNil != nil,
              config.postProcessing.remote.model?.blankToNil != nil else {
            XCTFail("postProcessing.remote.baseURL and model are required for remote eval.")
            return
        }

        let apiKeyOverride = ProcessInfo.processInfo.environment["TSUTAE_REMOTE_EVAL_API_KEY"]?.blankToNil
        let modelOverride = ProcessInfo.processInfo.environment["TSUTAE_REMOTE_EVAL_MODEL"]?.blankToNil
        let resultPath = ProcessInfo.processInfo.environment["TSUTAE_REMOTE_EVAL_RESULTS"]?.blankToNil
        let strictMode = ProcessInfo.processInfo.environment["TSUTAE_REMOTE_EVAL_STRICT"] == "1"
        var remoteConfig = config.postProcessing
        remoteConfig.enabled = true
        remoteConfig.mode = .remote
        remoteConfig.remote.enabled = true
        if let modelOverride {
            remoteConfig.remote.model = modelOverride
        }
        remoteConfig.dictionary.enabled = true
        remoteConfig.dictionary.useBuiltIn = true

        var report = EvalReport()
        var records: [RemoteEvalRecord] = []
        for testCase in Self.remoteEvalCases {
            let caseConfig = Config.TranscriptPostProcessingConfig(
                enabled: true,
                mode: .remote,
                defaultTask: testCase.task,
                remote: remoteConfig.remote,
                dictionary: remoteConfig.dictionary
            )
            let startedAt = CFAbsoluteTimeGetCurrent()
            let result = try await TranscriptPostProcessor.process(
                testCase.raw,
                config: caseConfig,
                language: config.stt.language,
                apiKeyOverride: apiKeyOverride
            )
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            let failures = TranscriptEval.evaluate(output: result.processedText, criteria: testCase.criteria)
            records.append(RemoteEvalRecord(
                id: testCase.id,
                task: testCase.task.rawValue,
                model: result.model ?? remoteConfig.remote.model ?? "unknown",
                elapsedMs: elapsedMs,
                passed: failures.isEmpty,
                failures: failures,
                dictionaryMatches: result.dictionaryMatches,
                output: result.processedText
            ))

            report.record(caseID: testCase.id, category: testCase.task.rawValue, failures: failures)
            print("""

            [remote-eval] \(testCase.id)
            task: \(testCase.task.rawValue)
            model: \(result.model ?? "unknown")
            elapsed_ms: \(String(format: "%.0f", elapsedMs))
            pass: \(failures.isEmpty)
            dictionary_matches: \(result.dictionaryMatches.joined(separator: ", "))
            output:
            \(result.processedText)
            """)
            if strictMode {
                XCTAssertTrue(failures.isEmpty, "\(testCase.id): \(failures.joined(separator: "; "))")
            }
        }
        print(report.summary(label: "Transcript configured remote eval"))
        if let resultPath {
            try Self.writeRemoteEvalRecords(records, to: URL(fileURLWithPath: resultPath))
        }
    }

    func testOpenAICompatibleTextClientToleratesUnescapedNewlinesInContent() async throws {
        let invalidButObservedResponse = """
        {"choices":[{"message":{"content":"Line one
        Line two"}}]}
        """
        let session = MockTextURLSession(
            data: Data(invalidButObservedResponse.utf8),
            statusCode: 200
        )
        let client = OpenAICompatibleTextClient(
            baseURL: URL(string: "https://example.com/v1")!,
            model: "test-model",
            session: session
        )

        let output = try await client.rewriteTranscript("raw output", task: .cleanDictation)

        XCTAssertEqual(output, "Line one\nLine two")
    }

    func testRemoteProcessorUsesConfiguredRemoteModel() async throws {
        let session = MockTextURLSession(
            data: Data(#"{"choices":[{"message":{"content":[{"type":"text","text":"- Decision: Ship docs."}]}}]}"#.utf8),
            statusCode: 200
        )
        let config = Config.TranscriptPostProcessingConfig(
            enabled: true,
            mode: .remote,
            defaultTask: .meetingNotes,
            remote: .init(
                enabled: true,
                baseURL: "https://example.com",
                model: "notes-model",
                apiKeyRef: nil
            )
        )

        let result = try await TranscriptPostProcessor.process(
            "we decided to ship docs",
            config: config,
            session: session
        )

        XCTAssertEqual(result.mode, .remote)
        XCTAssertEqual(result.task, .meetingNotes)
        XCTAssertEqual(result.provider, "openai_compatible")
        XCTAssertEqual(result.model, "notes-model")
        XCTAssertEqual(result.processedText, "- Decision: Ship docs.")
        XCTAssertEqual(session.lastRequest?.url?.absoluteString, "https://example.com/v1/chat/completions")
    }

    func testRemoteProcessorAppliesDictionaryAfterModelOutput() async throws {
        let session = MockTextURLSession(
            data: mockChatResponse("我们已完成 server token 和 git hub issue 配置，准备测试 codex hook。"),
            statusCode: 200
        )
        let config = Config.TranscriptPostProcessingConfig(
            enabled: true,
            mode: .remote,
            remote: .init(enabled: true, baseURL: "https://example.com", model: "test-model"),
            dictionary: .init(enabled: true, useBuiltIn: true)
        )

        let result = try await TranscriptPostProcessor.process(
            "raw",
            config: config,
            session: session
        )

        XCTAssertEqual(result.processedText, "我们已完成 Server token 和 GitHub Issue 配置，准备测试 Codex hook。")
        XCTAssertEqual(result.dictionaryMatches, ["git hub issue", "server token", "codex hook"])
    }

    func testRemoteCleanerPreservesSourceQuestionMarkWhenModelReturnsPeriod() async throws {
        let session = MockTextURLSession(
            data: mockChatResponse("请打开 GitHub Actions，看一下 JSON 配置有没有错。"),
            statusCode: 200
        )
        let config = Config.TranscriptPostProcessingConfig(
            enabled: true,
            mode: .remote,
            remote: .init(enabled: true, baseURL: "https://example.com", model: "test-model"),
            dictionary: .init(enabled: true, useBuiltIn: true)
        )

        let result = try await TranscriptPostProcessor.process(
            "请打开 git hub actions 逗号看一下 json 配置有没有错 问号",
            config: config,
            session: session
        )

        XCTAssertEqual(result.processedText, "请打开 GitHub Actions，看一下 JSON 配置有没有错？")
    }

    func testRemoteProcessorNormalizesEmptyOpenQuestionsAndMergedTerms() async throws {
        let session = MockTextURLSession(
            data: mockChatResponse("""
            ## 行动项
            - 测试 Server API STT 长录音功能。

            ## 开放问题
            - 长录音分段提示的具体交互细节待确认。
            """),
            statusCode: 200
        )
        let config = Config.TranscriptPostProcessingConfig(
            enabled: true,
            mode: .remote,
            remote: .init(enabled: true, baseURL: "https://example.com", model: "test-model"),
            dictionary: .init(enabled: true, useBuiltIn: true)
        )

        let result = try await TranscriptPostProcessor.process(
            "raw",
            config: config,
            session: session
        )

        XCTAssertEqual(result.processedText, "## 行动项\n- 测试 Server API、STT 长录音功能。")
        XCTAssertEqual(result.dictionaryMatches, ["server api stt"])
    }

    func testRemoteProcessorRemovesEmptyMarkdownSections() async throws {
        let session = MockTextURLSession(
            data: mockChatResponse("""
            ## 摘要
            - 发布前补文档。

            ## 决策
            无

            ## 行动项
            - 未指定：补 README。
            """),
            statusCode: 200
        )
        let config = Config.TranscriptPostProcessingConfig(
            enabled: true,
            mode: .remote,
            remote: .init(enabled: true, baseURL: "https://example.com", model: "test-model"),
            dictionary: .init(enabled: true, useBuiltIn: true)
        )

        let result = try await TranscriptPostProcessor.process(
            "发布前补 readme",
            config: config,
            task: .meetingNotes,
            session: session
        )

        XCTAssertEqual(result.processedText, "## 摘要\n- 发布前补文档。\n## 行动项\n- 未指定：补 README。")
    }

    private static func loadRemoteEvalConfig() throws -> Config {
        let environment = ProcessInfo.processInfo.environment
        if let configPath = environment["TSUTAE_REMOTE_EVAL_CONFIG"]?.blankToNil {
            return try ConfigLoader.load(from: URL(fileURLWithPath: configPath))
        }
        if let rootPath = environment["TSUTAE_REMOTE_EVAL_ROOT"]?.blankToNil {
            return try ConfigLoader.load(from: URL(fileURLWithPath: rootPath).appendingPathComponent("config.yml"))
        }
        let sandboxRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/dev.yanfch.Tsutae/Data/.tsutae")
        let sandboxConfig = sandboxRoot.appendingPathComponent("config.yml")
        if FileManager.default.fileExists(atPath: sandboxConfig.path) {
            return try ConfigLoader.load(from: sandboxConfig)
        }
        return try ConfigLoader.load()
    }

    private static func writeRemoteEvalRecords(_ records: [RemoteEvalRecord], to url: URL) throws {
        try writeJSONLRecords(records, to: url)
    }

    private static func writeJSONLRecords<T: Encodable>(_ records: [T], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lines = try records.map { record in
            String(data: try encoder.encode(record), encoding: .utf8) ?? "{}"
        }
        let text = lines.joined(separator: "\n") + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

private struct RuleEvalCase {
    let id: String
    let category: String
    let raw: String
    let expected: String
}

private struct LocalEvalRecord: Encodable {
    let id: String
    let category: String
    let raw: String
    let expected: String
    let output: String
    let elapsedMs: Double
    let passed: Bool
    let failures: [String]
    let provider: String
    let dictionaryMatches: [String]
}

private struct RemoteEvalCase {
    let id: String
    let task: Config.TranscriptPostProcessingTask
    let raw: String
    let remoteOutput: String
    let criteria: EvalCriteria
}

private struct RemoteEvalRecord: Encodable {
    let id: String
    let task: String
    let model: String
    let elapsedMs: Double
    let passed: Bool
    let failures: [String]
    let dictionaryMatches: [String]
    let output: String
}

private struct EvalCriteria {
    var exact: String?
    var mustContain: [String] = []
    var mustNotContain: [String] = []
    var maxLength: Int?
}

private enum TranscriptEval {
    static func evaluate(output: String, criteria: EvalCriteria) -> [String] {
        var failures: [String] = []
        if let exact = criteria.exact, output != exact {
            failures.append("expected exact '\(exact)' but got '\(output)'")
        }
        for value in criteria.mustContain where output.contains(value) == false {
            failures.append("missing '\(value)' in '\(output)'")
        }
        for value in criteria.mustNotContain where output.contains(value) {
            failures.append("unexpected '\(value)' in '\(output)'")
        }
        if let maxLength = criteria.maxLength, output.count > maxLength {
            failures.append("length \(output.count) exceeds \(maxLength)")
        }
        return failures
    }
}

private struct EvalReport {
    private var total = 0
    private var passed = 0
    private var failedByCategory: [String: Int] = [:]

    mutating func record(caseID: String, category: String, failures: [String]) {
        total += 1
        if failures.isEmpty {
            passed += 1
        } else {
            failedByCategory[category, default: 0] += 1
            print("Transcript eval failed \(caseID): \(failures.joined(separator: "; "))")
        }
    }

    func summary(label: String) -> String {
        let failed = total - passed
        if failedByCategory.isEmpty {
            return "\(label): \(passed)/\(total) passed"
        }
        let categories = failedByCategory
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        return "\(label): \(passed)/\(total) passed, \(failed) failed (\(categories))"
    }
}

private func mockChatResponse(_ content: String) -> Data {
    let object: [String: Any] = [
        "choices": [
            [
                "message": [
                    "content": content
                ]
            ]
        ]
    ]
    return try! JSONSerialization.data(withJSONObject: object)
}

private extension Data {
    func containsASCII(_ string: String) -> Bool {
        range(of: Data(string.utf8)) != nil
    }
}

private extension String {
    var blankToNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private final class MockTextURLSession: URLSessionProtocol, @unchecked Sendable {
    private let data: Data
    private let statusCode: Int
    var lastRequest: URLRequest?

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
