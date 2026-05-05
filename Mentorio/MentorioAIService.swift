//
//  MentorioAIService.swift
//  Mentorio
//

import Foundation
import SwiftUI

// MARK: - Public Response Model

struct FocusResponse: Codable {
	let topics: [String]?
	let highlight: String?
	let insight: String?
	let question: String?
	let choices: [String]?
}

// MARK: - Continuation Context

// StepIntensity kept for source compatibility but no longer used in prompts
enum StepIntensity {
    case micro
    case normal
}

struct ContinuationContext {
    let pastAction: String
    let pastNote: String?
    let contextSummary: String?
    // intensity kept for backwards compat but ignored in logic
    let intensity: StepIntensity

    init(pastAction: String, pastNote: String? = nil, contextSummary: String? = nil, intensity: StepIntensity = .normal) {
        self.pastAction = pastAction
        self.pastNote = pastNote
        self.contextSummary = contextSummary
        self.intensity = intensity
    }
}

// MARK: - Legacy ChatRequest (kept for public signatures)

struct ChatRequest: Encodable {
    struct ChatMessage: Encodable {
        let role: String
        let content: String
    }
}

// MARK: - Config & OpenAI Models

struct AIConfig {
    let baseURL: URL
    let apiKey: String
    let model: String
}

private struct OpenAIChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let max_tokens: Int?
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String?
            let content: String?
        }
        let message: Message?
    }
    let choices: [Choice]?
}

// MARK: - AI Service

enum MentorioAIService {
	private enum MentorioIntent: String {
		case taskProcrastination = "task_procrastination"
		case decisionParalysis = "decision_paralysis"
		case preconditionsMissing = "preconditions_missing"
		case vagueOverwhelm = "vague_overwhelm"
	}

	private struct IntentAnalysisResponse: Decodable {
		let intent: String
		let isHighStakes: Bool?
		let missingInfo: String?
	}

	private struct IntentAnalysis {
		let intent: MentorioIntent
		let isHighStakes: Bool
		let missingInfo: String?
	}

	private static var intentCache: [String: IntentAnalysis] = [:]
	private static let intentCacheQueue = DispatchQueue(label: "MentorioAIService.intentCache")

	private static func cacheKey(
		text: String,
		selectedTopic: String?,
		userAnswer: String?
	) -> String {
		[text, selectedTopic ?? "", userAnswer ?? ""].joined(separator: "|")
	}

    private static func currentConfig() throws -> AIConfig {
        let customBase = UserDefaults.standard.string(forKey: "customAIBaseURL")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let customKey = UserDefaults.standard.string(forKey: "customAIKey")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let customModel = UserDefaults.standard.string(forKey: "customAIModel")?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let base = customBase, !base.isEmpty,
           let key = customKey, !key.isEmpty,
           let model = customModel, !model.isEmpty,
           let url = URL(string: base) {
            return AIConfig(baseURL: url, apiKey: key, model: model)
        }

        // Default OpenRouter config
        let rawKey = Bundle.main.infoDictionary?["OPENROUTER_API_KEY"] as? String ?? ""
        let defaultKey = rawKey.trimmingCharacters(in: CharacterSet(charactersIn: " \"'\n\t\r"))
        
        guard !defaultKey.isEmpty else {
            throw MentorioAIError.missingAPIKey
        }
        
        guard let url = URL(string: "https://openrouter.ai/api") else {
            throw MentorioAIError.invalidURL
        }
        
        return AIConfig(baseURL: url, apiKey: defaultKey, model: "openrouter/auto")
    }

	// MARK: - Public API (Signatures preserved)

	/// LEGACY: читает только ранее сохранённый анализ из intentCache.
	/// Не вызывает LLM сам по себе. Новому коду лучше использовать analyzeIntent(for:).
	static func classifyIntent(
		for text: String,
		selectedTopic: String? = nil,
		userAnswer: String? = nil
	) -> String {
		let key = cacheKey(text: text, selectedTopic: selectedTopic, userAnswer: userAnswer)
		if let cached = intentCacheQueue.sync(execute: { intentCache[key] }) {
			return cached.intent.rawValue
		}
		return MentorioIntent.taskProcrastination.rawValue
	}

	/// LEGACY: читает только ранее сохранённый анализ из intentCache.
	/// Не вызывает LLM сам по себе. Новому коду лучше использовать analyzeIntent(for:).
	static func isHighStakesContext(
		for text: String,
		selectedTopic: String? = nil,
		userAnswer: String? = nil
	) -> Bool {
		let key = cacheKey(text: text, selectedTopic: selectedTopic, userAnswer: userAnswer)
		if let cached = intentCacheQueue.sync(execute: { intentCache[key] }) {
			return cached.isHighStakes
		}
		return false
	}

	static func analyzeIntent(
		for text: String
	) async throws -> (intent: String, isHighStakes: Bool, missingInfo: String?) {
		let analysis = try await analyzeIntent(
			text: text,
			selectedTopic: nil,
			userAnswer: nil
		)
		return (
			intent: analysis.intent.rawValue,
			isHighStakes: analysis.isHighStakes,
			missingInfo: analysis.missingInfo
		)
	}

	static func getCoreHighlightChoices(
		for text: String,
		selectedTopic: String? = nil,
		userAnswer: String? = nil,
		clarifyingAttempts: Int = 0,
        isFastTrack: Bool = false,
        contextSummary: String? = nil,
        continuation: ContinuationContext? = nil
	) async throws -> FocusResponse {
        // Stage A (analyzeIntent) removed in Sprint 3 (#6).
        // It was a second API call used only to pass intent.rawValue into the prompt.
        // The Stage B prompt already has full context via Priority Rules.
		let prompt = buildFocusPrompt(
			text: text,
			selectedTopic: selectedTopic,
			userAnswer: userAnswer,
			clarifyingAttempts: clarifyingAttempts,
            isFastTrack: isFastTrack,
            contextSummary: contextSummary,
            continuation: continuation
		)

		let raw = try await requestChatCompletion(prompt: prompt)
		let cleaned = try cleanJSONText(raw)
		guard let data = cleaned.data(using: .utf8) else {
			throw MentorioAIError.invalidResponse
		}

		let decoded = try JSONDecoder().decode(FocusResponse.self, from: data)
		return try sanitizeFocusResponse(decoded)
	}

	static func getOneAction(
		for choice: String,
		braindump: String,
		highlight: String,
		insight: String,
		selectedTopic: String? = nil
	) async throws -> String {
        // intentCache lookup removed: Stage A no longer runs, cache is always empty (#6).

		let prompt = """
  Ты — Mentorio, прямой и приземленный ментор по поведенческой активации.
  Твоя задача: дать ОДНО выполнимое физическое действие на 10–15 минут.
  
  Контекст пользователя:
  — Брайндамп: \(braindump)
  — Ключевая фраза (highlight): \(highlight)
  — Фактическая ситуация (insight): \(insight)
  — Выбранная тактика (choice): \(choice)
  — Выбранный фокус (selected_topic): \(selectedTopic ?? "[не выбран]")
  
  ЖЁСТКОЕ ПРАВИЛО ФОКУСА:
  - Игнорируй все другие темы из брайндампа, кроме выбранной тактики и выбранного фокуса.
  - Действие должно продвигать ТОЛЬКО тактику "\(choice)" в рамках выбранной темы.
  - Если выбор про квартиру — не трогай музыку и язык. Если выбор про музыку — не трогай квартиру и прочее.
  
  ОБЯЗАТЕЛЬНЫЕ ПРАВИЛА:
          - Действие должно оставлять наблюдаемый артефакт во внешнем мире (файл, заметка, сообщение, заявка, сохранённый вариант и т.п.).
          - Начни с глагола прямого действия (открой, напиши, отправь, создай, запусти).
          - Лимит времени 10–15 минут.
          - Никаких капитальных коммитов в первом шаге (не покупать, не увольняться, не подписывать договор, не переезжать).
  
          КРИТИЧЕСКОЕ ПРАВИЛО (POINT OF NO RETURN):
          - Это финальный этап. ТЕБЕ СТРОГО ЗАПРЕЩЕНО ЗАДАВАТЬ ЛЮБЫЕ ВОПРОСЫ.
          - СТРОГО ЗАПРЕЩЕНО предлагать обсудить, уточнить детали или продолжать диалог.
          - Если твой ответ содержит знак вопроса "?" — это критическая ошибка.
  
          ФОРМАТ ОТВЕТА (СТРОГО):
          - Только ОДНА прямая команда-действие.
          - Без приветствий, без пояснений, без точек в конце, без кавычек и нумерации.
  
  """

		let raw = try await requestChatCompletion(prompt: prompt)
		let cleaned = sanitizePlainText(raw)
		guard !cleaned.isEmpty else {
			throw MentorioAIError.emptyResponse
		}
		return cleaned
	}

    static func summarizeContext(
        braindump: String,
        history: [ChatRequest.ChatMessage]
    ) async throws -> String {
        let historyText = history.map { "\($0.role == "user" ? "Юзер" : "Ментор"): \($0.content)" }.joined(separator: "\n")
        
        let prompt = """
        Сформируй краткое резюме ситуации пользователя (2–3 предложения, максимум 60–80 слов).
        Кто он, в чем главная проблема, какая цель.
        Используй только факты из текста.
        Не добавляй интерпретаций и советов.
        Не используй обращений по имени, если оно не указано явно.

        Входные данные:
        — Брайндамп: \(braindump)
        — Фрагменты диалога:
        \(historyText)
        """
        
        let raw = try await requestChatCompletion(prompt: prompt)
        return sanitizePlainText(raw)
    }

	// MARK: - Intent Analysis (Stage A)

	private static func analyzeIntent(
		text: String,
		selectedTopic: String?,
		userAnswer: String?
	) async throws -> IntentAnalysis {
		let prompt = """
		OUTPUT ONLY VALID JSON. ZERO CONVERSATIONAL TEXT. NO MARKDOWN. NO EXPLANATIONS.

		Ты — Mentorio. Проведи краткую классификацию ввода.
		Верни JSON строго по схеме:
		{
		  "intent": "task_procrastination" | "decision_paralysis" | "preconditions_missing" | "vague_overwhelm",
		  "isHighStakes": true/false,
		  "missingInfo": "что нужно уточнить" или null
		}

		Правила:
		- isHighStakes=true, если решение связано с крупными жизненными изменениями или большими деньгами.
		- missingInfo: кратко укажи, чего не хватает для решения; если все ясно — null.

		Ввод:
		— Текст: \(text)
		— Selected topic: \(selectedTopic ?? "[нет]")
		— User answer: \(userAnswer ?? "[нет]")
		"""

		let raw = try await requestChatCompletion(prompt: prompt)
		let cleaned = try cleanJSONText(raw)
		guard let data = cleaned.data(using: .utf8) else {
			throw MentorioAIError.invalidResponse
		}

		let decoded = try JSONDecoder().decode(IntentAnalysisResponse.self, from: data)
		let intent = MentorioIntent(rawValue: decoded.intent) ?? .taskProcrastination
		let missingInfo = decoded.missingInfo?.trimmingCharacters(in: .whitespacesAndNewlines)
		let finalMissingInfo = (missingInfo?.isEmpty == true) ? nil : missingInfo

		return IntentAnalysis(
			intent: intent,
			isHighStakes: decoded.isHighStakes ?? false,
			missingInfo: finalMissingInfo
		)
	}

	// MARK: - Focus Prompt (Stage B)

	private static func buildFocusPrompt(
		text: String,
		selectedTopic: String?,
		userAnswer: String?,
		clarifyingAttempts: Int,
        isFastTrack: Bool,
        contextSummary: String?,
        continuation: ContinuationContext? = nil
	) -> String {
		return """
        OUTPUT ONLY VALID JSON. ZERO CONVERSATIONAL TEXT. NO MARKDOWN.
        
        Ты — Mentorio, жесткий ментор по поведенческой активации. Твоя задача — перевести хаос мыслей пользователя в одну конкретную физическую тактику и затем в действие на 10–15 минут.
        
        ФОРМАТ ОТВЕТА:
        {
          "topics": null или ["Тема 1", "Тема 2"],
          "highlight": null или "точная цитата пользователя",
          "insight": null или "1-2 фактических предложения",
          "question": null или "короткий уточняющий вопрос",
          "choices": null или ["Тактика 1", "Тактика 2"]
        }
        
        PRIORITY RULES (APPLY IN THIS ORDER):
        
        1. TOPICS:
           IF selected_topic == null AND multiple problems in text:
           - Return only "topics" (2-3 labels), optional "highlight"/"insight".
           - "question" and "choices" MUST be null.
        
        2. FORCED_CHOICES:
           IF attempts >= 2 OR is_fast_track == true:
           - "question" MUST be null.
           - "choices" MUST contain exactly 2 tactics.
        
        3. CLARIFICATION:
           IF selected_topic != null AND attempts < 2 AND is_fast_track == false:
           - You MAY return one short factual "question".
           - If you ask a question, "choices" MUST be null.
        
        4. CHOICES_FORMAT:
           IF "choices" is not null:
           - Exactly 2 items, imperative commands (10-15 minutes, ending with external artifact).
           - Forbidden phrases: "как насчет", "может быть", "попробуй".
        
        5. NO_SOFT_COACHING:
           - Do not use empathy/support phrases ("я понимаю", "это нормально").
           - Be dry, direct, and factual.
        
        ТЕХНИЧЕСКИЙ КОНТЕКСТ:
        — Selected Topic: \(selectedTopic ?? "null")
        — Clarifying attempts: \(clarifyingAttempts)
        — Is Fast-Track: \(isFastTrack)
        — Context Summary: \(contextSummary ?? "[Нет резюме, используй исходный текст]")
        
        \(continuation != nil ? """
        КОНТЕКСТ ПРОДОЛЖЕНИЯ — ПОЛЬЗОВАТЕЛЬ СДЕЛАЛ ШАГ И ХОЧЕТ СЛЕДУЮЩИЙ:
        — Выполненное действие: \(continuation!.pastAction)
        — Заметка пользователя: \(continuation!.pastNote ?? "нет")
        — Резюме ситуации: \(continuation!.contextSummary ?? contextSummary ?? "нет")

        ФОРМАТ ОТВЕТА ДЛЯ ПРОДОЛЖЕНИЯ:
        Верни JSON с полем "choices": null и полем "question": null.
        Верни только "highlight" = констатация факта победы (1 предложение, без похвалы: "Шаг сделан: <pastAction>."),
        "insight" = краткий вывод о контексте (1 предложение),
        а в поле "choices" — одно конкретное следующее физическое действие на 10–15 минут с артефактом во внешнем мире.
        Всё в духе Mentorio: жёстко, без воды, без эмодзи, без метафор.
        """ : "")
        
        ИСХОДНЫЕ ДАННЫЕ ЮЗЕРА:
        Брайндамп:
        \(text)
        
        Последний ответ:
        \(userAnswer ?? "null")
        """
	}

    // MARK: - Networking

    private static let systemPersona = "Ты — Mentorio, жесткий, но заботливый ментор по поведенческой активации. Отвечай максимально кратко, без вежливости и вводных фраз. Не пиши 'привет', 'конечно' и 'давай разберемся'. Твой лимит — 3 предложения. Сразу переходи к сути ответа."

    static func buildMessages(
        currentPrompt: String,
        history: [ChatRequest.ChatMessage] = [],
        summary: String? = nil
    ) -> [ChatRequest.ChatMessage] {
        var messages: [ChatRequest.ChatMessage] = []
        
        // Скользящее окно (последние 4 реплики из истории)
        let windowSize = 4
        let recentHistory = history.suffix(windowSize)
        messages.append(contentsOf: recentHistory)
        
        // Текущий запрос пользователя
        messages.append(ChatRequest.ChatMessage(role: "user", content: currentPrompt))
        
        return messages
    }

    private static func postChat(request: OpenAIChatRequest, config: AIConfig) async throws -> String {
        let url = config.baseURL.appendingPathComponent("/v1/chat/completions")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        
        let requestData = try JSONEncoder().encode(request)
        urlRequest.httpBody = requestData

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

        let rawResponseString = String(data: data, encoding: .utf8) ?? "Unable to decode raw response as UTF-8 string."
        print("--- [RAW RESPONSE FROM MODEL] ---")
        print("HTTP Status: \(statusCode)")
        print("Body: \(rawResponseString)")
        print("---------------------------------")

        guard 200..<300 ~= statusCode else {
            print("🚨 ОШИБКА API (Код \(statusCode)): \(rawResponseString)")
            throw MentorioAIError.invalidResponse
        }

        do {
            let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
            guard let text = decoded.choices?.first?.message?.content, !text.isEmpty else {
                throw MentorioAIError.emptyResponse
            }
            return text
        } catch {
            print("🚨 ОШИБКА ДЕКОДИРОВАНИЯ JSON: \(String(describing: error))")
            print("Сырой ответ сервера: \(rawResponseString)")
            throw MentorioAIError.invalidJSONResponse
        }
    }

    private static func requestChatCompletion(
        prompt: String, 
        history: [ChatRequest.ChatMessage] = [],
        summary: String? = nil
    ) async throws -> String {
        let config = try currentConfig()
        let legacyMessages = buildMessages(currentPrompt: prompt, history: history, summary: summary)
        
        var messages: [OpenAIChatRequest.Message] = []
        
        var sysText = systemPersona
        if let summary = summary, !summary.isEmpty {
            sysText += "\nКонтекст ситуации: \(summary)"
        }
        
        messages.append(OpenAIChatRequest.Message(role: "system", content: sysText))
        
        for msg in legacyMessages {
            let role = (msg.role == "assistant" || msg.role == "model") ? "assistant" : "user"
            messages.append(OpenAIChatRequest.Message(role: role, content: msg.content))
        }

        let request = OpenAIChatRequest(
            model: config.model,
            messages: messages,
            max_tokens: 400
        )

        return try await postChat(request: request, config: config)
    }

	// MARK: - Sanitizers (basic only)

	private static func cleanJSONText(_ raw: String) throws -> String {
		var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

		if text.hasPrefix("```") {
			if let firstFenceRange = text.range(of: "```"),
			   let lastFenceRange = text.range(of: "```", options: .backwards),
			   firstFenceRange.lowerBound != lastFenceRange.lowerBound {
				let start = text.index(after: firstFenceRange.upperBound)
				let inner = text[start..<lastFenceRange.lowerBound]
				text = String(inner).trimmingCharacters(in: .whitespacesAndNewlines)
			}
		}

		if let firstBrace = text.firstIndex(of: "{"),
		   let lastBrace = text.lastIndex(of: "}") {
			text = String(text[firstBrace...lastBrace])
		} else {
			throw MentorioAIError.invalidJSONResponse
		}

		if text == "{}" || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			throw MentorioAIError.invalidJSONResponse
		}

		return text
	}

	private static func sanitizeFocusResponse(_ response: FocusResponse) throws -> FocusResponse {
		let topics = sanitizeStringList(response.topics)
		let choices = sanitizeStringList(response.choices)
		let highlight = sanitizeString(response.highlight)
		let insight = sanitizeString(response.insight)
		let question = sanitizeString(response.question)

		let trimmedChoices = choices != nil ? Array(choices!.prefix(2)) : nil

		let result = FocusResponse(
			topics: topics,
			highlight: highlight,
			insight: insight,
			question: question,
			choices: trimmedChoices
		)

		let hasTopics = result.topics?.isEmpty == false
		let hasChoices = result.choices?.isEmpty == false
		let hasQuestion = result.question?.isEmpty == false

		if !hasTopics && !hasChoices && !hasQuestion {
			throw MentorioAIError.incompleteResponse
		}

		return result
	}

	private static func sanitizeString(_ value: String?) -> String? {
		guard let value else { return nil }
		let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
		return cleaned.isEmpty ? nil : cleaned
	}

	private static func sanitizeStringList(_ values: [String]?) -> [String]? {
		guard let values else { return nil }
		let cleaned = values
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
		return cleaned.isEmpty ? nil : cleaned
	}

	private static func sanitizePlainText(_ raw: String) -> String {
		var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

		if text.hasPrefix("```") {
			if let firstFenceRange = text.range(of: "```"),
			   let lastFenceRange = text.range(of: "```", options: .backwards),
			   firstFenceRange.lowerBound != lastFenceRange.lowerBound {
				let start = text.index(after: firstFenceRange.upperBound)
				let inner = text[start..<lastFenceRange.lowerBound]
				text = String(inner).trimmingCharacters(in: .whitespacesAndNewlines)
			}
		}

		let wrapperPairs: [(Character, Character)] = [
			("\"", "\""),
			("'", "'"),
			("«", "»"),
			("“", "”")
		]
		if let first = text.first,
		   let last = text.last,
		   wrapperPairs.contains(where: { $0.0 == first && $0.1 == last }),
		   text.count >= 2 {
			text.removeFirst()
			text.removeLast()
			text = text.trimmingCharacters(in: .whitespacesAndNewlines)
		}

		while let last = text.last, ".!?".contains(last) {
			text.removeLast()
			text = text.trimmingCharacters(in: .whitespacesAndNewlines)
		}

		return text
	}

#if DEBUG
	static func runContextAnchoringRegressionSuite() -> [String] {
		return ["SKIPPED: regression suite not implemented in new AI service"]
	}
#endif
}

// MARK: - Error Type

enum MentorioAIError: Error {
	case invalidURL
	case missingAPIKey
	case invalidResponse
	case emptyResponse
	case invalidJSONResponse
	case incompleteResponse
}

extension MentorioAIError: LocalizedError {
	var errorDescription: String? {
		switch self {
		case .invalidURL:
			return "Неверный адрес AI-сервиса"
		case .missingAPIKey:
			return "Не найден OPENROUTER_API_KEY или локальный ключ. Проверь настройки приложения"
		case .invalidResponse:
			return "AI-сервис вернул некорректный ответ"
		case .emptyResponse:
			return "AI-сервис вернул пустой ответ"
		case .invalidJSONResponse:
			return "AI-сервис вернул невалидный JSON"
		case .incompleteResponse:
			return "AI-сервис вернул неполный ответ"
		}
	}
}
