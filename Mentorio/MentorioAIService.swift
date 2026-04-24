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

// MARK: - OpenRouter Request/Response Models

struct ChatRequest: Encodable {
	let model: String
	let messages: [ChatMessage]

	struct ChatMessage: Encodable {
		let role: String
		let content: String
	}
}

struct ChatResponse: Decodable {
	let choices: [ChatChoice]

	struct ChatChoice: Decodable {
		let message: ChatMessageResponse

		struct ChatMessageResponse: Decodable {
			let content: String
		}
	}
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

	private static func apiKey() throws -> String {
		guard let key = Bundle.main.infoDictionary?["OPENROUTER_API_KEY"] as? String,
			  !key.isEmpty else {
			throw MentorioAIError.missingAPIKey
		}
		return key
	}

	private static let endpoint = "https://openrouter.ai/api/v1/chat/completions"
	private static let model = "google/gemini-2.0-flash-001"

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
		clarifyingAttempts: Int = 0
	) async throws -> FocusResponse {
		let analysis = try await analyzeIntent(
			text: text,
			selectedTopic: selectedTopic,
			userAnswer: userAnswer
		)

		let key = cacheKey(text: text, selectedTopic: selectedTopic, userAnswer: userAnswer)
		intentCacheQueue.sync {
			intentCache[key] = analysis
		}

		let prompt = buildFocusPrompt(
			text: text,
			selectedTopic: selectedTopic,
			userAnswer: userAnswer,
			clarifyingAttempts: clarifyingAttempts,
			analysis: analysis
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
		let key = cacheKey(text: braindump, selectedTopic: selectedTopic, userAnswer: nil)
		let cached = intentCacheQueue.sync(execute: { intentCache[key] })
		let highStakesHint = cached?.isHighStakes == true
			? "HIGH-STAKES MODE: stay strictly within the selected focus and choice; first step must be reversible and fact-checking."
			: ""

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
		\(highStakesHint)

		ФОРМАТ ОТВЕТА:
		- Ровно одна команда.
		- Без кавычек, без точки в конце, без пояснений и нумерации.
		"""

		let raw = try await requestChatCompletion(prompt: prompt)
		let cleaned = sanitizePlainText(raw)
		guard !cleaned.isEmpty else {
			throw MentorioAIError.emptyResponse
		}
		return cleaned
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
		analysis: IntentAnalysis
	) -> String {
		let missingInfoHint = analysis.missingInfo != nil
			? "Недостающие данные: \(analysis.missingInfo!)"
			: "Недостающие данные: null"

		if selectedTopic?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
			return """
			OUTPUT ONLY VALID JSON. ZERO CONVERSATIONAL TEXT. NO MARKDOWN. NO EXPLANATIONS.

			Ты — Mentorio. Жесткий, структурный ментор. Твоя задача — не обсуждать жизнь в целом, а вытащить 1 фокус и перевести его в физическое действие.

			ФОРМАТ ОБЪЕКТА (СТРОГО):
			{
			  "topics": null или ["Тема 1", "Тема 2", "Тема 3"],
			  "highlight": null или "точная цитата из текста юзера",
			  "insight": null или "1-2 фактических предложения",
			  "question": null или "уточняющий вопрос",
			  "choices": null или ["Вариант 1", "Вариант 2"]
			}

			ЛОГИКА ВЫБОРА РЕЖИМА:

			1) Если в тексте 2+ независимых направлений (например: жильё, музыка, язык, учеба):
			   - Верни только:
			     - "topics": список коротких ярлыков (2–4 слова) по этим направлениям,
			     - "highlight": одна фраза, которая честно подводит итог,
			     - "insight": 1–2 факта про общий паттерн (например, избегание действий).
			   - "choices": null
			   - "question": null

			2) Если в тексте по сути одно доминирующее направление:
			   - "topics": null
			   - "highlight": точная цитата
			   - "insight": факт
			   - "choices": РОВНО 2 варианта для ЭТОЙ темы
			   - "question": либо null, либо один короткий уточняющий вопрос (если без него нельзя двигаться дальше).

			ПРАВИЛА ДЛЯ topics:
			- Каждая тема — от 2 до 4 слов, без сложных оборотов.
			- Темы — это ярлыки фокуса ("поиск квартиры", "музыка / треки", "сербский язык").
			- Не делай больше 3 тем. Если направлений больше — выбери 2–3 самых явных конфликта.

			ПРАВИЛА ДЛЯ choices (если они всё-таки нужны на этом шаге):
			- Ровно 2 варианта.
			- Только физические действия на 10–15 минут.
			- Каждый вариант заканчивается артефактом (файл, заметка, сообщение, заявка, сохранённый вариант).
			- Без капитальных коммитов в первом шаге.

			Контекст:
			— Intent: \(analysis.intent.rawValue)
			— High-stakes: \(analysis.isHighStakes)
			— \(missingInfoHint)
			— Clarifying attempts: \(clarifyingAttempts)

			Текст пользователя:
			\(text)

			Selected topic:
			\(selectedTopic ?? "[нет]")

			User answer:
			\(userAnswer ?? "[нет]")
			"""
		}

		return """
		OUTPUT ONLY VALID JSON. ZERO CONVERSATIONAL TEXT. NO MARKDOWN. NO EXPLANATIONS.

		Ты — Mentorio. Сейчас пользователь уже выбрал фокус: работай ТОЛЬКО с этой темой и игнорируй остальные части брайндампа.

		ФОРМАТ ОБЪЕКТА (СТРОГО):
		{
		  "topics": null,
		  "highlight": null или "точная цитата из текста юзера",
		  "insight": null или "1-2 фактических предложения",
		  "question": null или "уточняющий вопрос",
		  "choices": null или ["Вариант 1", "Вариант 2"]
		}

		ПРАВИЛА:
		- Игнорируй все другие темы из текста, кроме выбранной.
		- Не возвращай topics, только highlight/insight/question/choices.
		- choices: Ровно 2 варианта, оба про ОДНУ выбранную тему.
		- Только физические действия на 10–15 минут.
		- Каждый вариант заканчивается артефактом (файл, заметка, сообщение, заявка, сохранённый вариант).
		- Без капитальных коммитов в первом шаге.
		- Никаких когнитивных команд ("подумай", "проанализируй", "прикинь").

		Контекст:
		— Выбранная тема (selected_topic): \(selectedTopic ?? "[не выбран]")
		— Intent: \(analysis.intent.rawValue)
		— High-stakes: \(analysis.isHighStakes)
		— Clarifying attempts: \(clarifyingAttempts)

		Исходный текст пользователя:
		\(text)

		User answer:
		\(userAnswer ?? "[нет]")
		"""
	}

	// MARK: - Networking (same as old)

	private static func postToOpenRouter(requestBody: Data) async throws -> Data {
		guard let url = URL(string: endpoint) else {
			throw MentorioAIError.invalidURL
		}

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(try apiKey())", forHTTPHeaderField: "Authorization")
		request.setValue("https://mentorio.app", forHTTPHeaderField: "HTTP-Referer")
		request.setValue("Mentorio", forHTTPHeaderField: "X-Title")
		request.httpBody = requestBody

		let (data, response) = try await URLSession.shared.data(for: request)
		let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

		guard 200..<300 ~= statusCode else {
			let errorBody = String(data: data, encoding: .utf8) ?? "Нет данных"
			print("🚨 ОШИБКА API OpenRouter (Код \(statusCode)): \(errorBody)")
			throw MentorioAIError.invalidResponse
		}

		return data
	}

	private static func requestChatCompletion(prompt: String) async throws -> String {
		let body = ChatRequest(
			model: model,
			messages: [ChatRequest.ChatMessage(role: "user", content: prompt)]
		)

		let requestData = try JSONEncoder().encode(body)
		let responseData = try await postToOpenRouter(requestBody: requestData)

		let decoded = try JSONDecoder().decode(ChatResponse.self, from: responseData)
		guard let text = decoded.choices.first?.message.content,
			  !text.isEmpty else {
			throw MentorioAIError.emptyResponse
		}
		return text
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
			return "Не найден OPENROUTER_API_KEY. Проверь настройки приложения"
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
