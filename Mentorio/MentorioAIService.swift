//
//  MentorioAIService.swift
//  Mentorio
//

import Foundation
import SwiftUI

// MARK: - Mirror Response (v2.0)

struct MirrorResponse: Codable {
	let intake: String     // 3-5 слов: подтверждение приёма ("Дедлайн. Ясно.")
	let highlight: String  // Суть хаоса, 1-2 предложения
	let action: String     // Одно действие, 10-15 мин
	let emoji: String      // Одна эмодзи для карточки архива
}

// MARK: - Legacy Response Model (v1 — still used by NoteCardView)

struct FocusResponse: Codable {
	let topics: [String]?
	let highlight: String?
	let insight: String?
	let question: String?
	let choices: [String]?
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

	// MARK: - v2.0 Public API

	/// One-shot braindump → mirror response. Returns highlight + action + emoji.
	/// This is the ONLY AI call in the v2.0 flow.
	static func getMirrorResponse(
		for text: String,
		retryHint: String? = nil
	) async throws -> MirrorResponse {
		let prompt = buildMirrorPrompt(text: text, retryHint: retryHint)
		let raw = try await requestChatCompletion(prompt: prompt)
		let cleaned = try cleanJSONText(raw)
		guard let data = cleaned.data(using: .utf8) else {
			throw MentorioAIError.invalidResponse
		}

		let decoded = try JSONDecoder().decode(MirrorResponse.self, from: data)

		// Validate: highlight and action must be non-empty
		let i = decoded.intake.trimmingCharacters(in: .whitespacesAndNewlines)
		let h = decoded.highlight.trimmingCharacters(in: .whitespacesAndNewlines)
		let a = decoded.action.trimmingCharacters(in: .whitespacesAndNewlines)
		let e = decoded.emoji.trimmingCharacters(in: .whitespacesAndNewlines)

		guard !h.isEmpty, !a.isEmpty else {
			throw MentorioAIError.incompleteResponse
		}

		return MirrorResponse(
			intake: i.isEmpty ? "Принял." : i,
			highlight: h,
			action: a,
			emoji: e.isEmpty ? "⚡" : e
		)
	}

	// MARK: - Mirror Prompt (v2.0)

    private static func buildMirrorPrompt(
        text: String,
        retryHint: String?
    ) -> String {
        var prompt = """
    OUTPUT ONLY VALID JSON. ZERO CONVERSATIONAL TEXT. NO MARKDOWN.

    Ты — Mentorio, требовательный союзник по поведенческой активации.
    Твоя работа состоит из трёх этапов:

    ═══ ЭТАП 0: ПРИЁМ (intake) ═══
    Дай богатый, контекстно-зависимый, психологически точный и глубокий партнерский отклик.
    Лимит: до 70 слов (обычно 2-4 предложения).
    Твой тон — партнерский, сильный, требовательный, лаконичный. Без сюсюканья, сочувствия и жалости, но показывающий глубокое понимание механики сопротивления человека в этой конкретной ситуации.
    Объясни пользователю, ПОЧЕМУ он застрял (перфекционизм, страх чистого листа, суета, бегство в мелкие дела, ожидание идеального настроя), возвращая ему контроль и авторитет над ситуацией.
    Не пытайся превратить диалог в сеанс у психолога (избегай заумного психотерапевтического жаргона: "внутренний ребенок", "токсичный стыд", "гештальт" и т.д.). Говори простым, сильным бытовым языком.
    НЕ повторяй дословно фразы пользователя. Выдели ключевое психологическое препятствие.

    Если это первая попытка (retryHint равен nil):
    Сформулируй причину ступора и направь энергию пользователя на преодоление первого шага.
    Примеры:
    - "Ясно. Соцсети — это просто твое убежище от страха чистого листа. Каждый раз, когда ты думаешь о масштабе проекта, твой мозг паникует и уводит тебя за дешевым дофамином. Нам не нужна идеальная работа, нужен сырой черновик. Вот твоя точка входа:"
    - "Ты прячешься за мелкой рутиной и планированием, чтобы не касаться сложного решения по бюджету. Это классический перфекционизм. Давай уберем планку до нуля и просто зафиксируем факты на бумаге. Сделаем это:"

    Если это повторная попытка (retryHint НЕ равен nil):
    Обязательно отреагируй на отказ от предыдущего действия. Покажи понимание того, что предложенное ранее действие вызвало слишком высокое сопротивление или было не в тему, объясни ПОЧЕМУ это нормально в контексте прокрастинации, и расскажи, как мы сейчас перестроим подход или снизим порог входа, чтобы обойти этот баг мышления.
    Примеры:
    - "Понял. Созваниваться без готовой структуры разговора для тебя сейчас — слишком высокий порог страха, поэтому ты саботируешь. Справедливо, давай не будем насиловать мозг. Давай уберем звонок и снизим планку до минимума: напишем сценарий-шпаргалку для себя. Сделаем так:"
    - "Хорошо, писать текст с ходу в файл — перфекционизм все еще блокирует твои мысли. Давай обойдем этот баг: уберем необходимость формулировать связные предложения. Выпишем просто ключевые тезисы на листочке. Смотри:"

    ═══ ЭТАП 1: ЗЕРКАЛО (highlight) ═══
    Вскрой суть — что именно стоит между пользователем и действием (СТРОГО до 15 слов на "ты").
    Поставь честный, острый, сухой диагноз блокирующему фактору без самооправданий, жалости и лишней воды. Это должен быть краткий, емкий ярлык уловки ума, который отлично читается на карточке и красиво ложится в историю побед.
    Примеры:
    - "Ты прячешься за уборкой и бытовой суетой, чтобы отложить подготовку к экзамену."
    - "Страх чистого листа заставляет тебя бесконечно собирать референсы вместо написания кода."
    - "Ты откладываешь сложный звонок клиенту из-за страха выглядеть некомпетентно."
    Если в тексте несколько проблем — выбери одну, которую проще всего сдвинуть прямо сейчас.

    ═══ ЭТАП 2: ОДИН ШАГ (action) ═══
    На основе зеркала дай ОДНО конкретное физическое действие на 10-15 минут, логически вытекающее из сути.
    Действие ОБЯЗАНО заканчиваться осязаемым наблюдаемым артефактом (написанный от руки конспект, сохранённый файл, отправленное сообщение, сфотографированный лист).
    Примеры артефактов:
    "Прочитай 10 страниц" — не артефакт. "Прочитай 10 страниц и запиши ключевые термины на бумагу" — артефакт.
    Указывай конкретный объём: не "прочитай главу", а "прочитай 10 страниц". Не "напиши текст", а "напиши 3 абзаца".

    ═══ ФОРМАТ ОТВЕТА (JSON, СТРОГО) ═══
    {
      "intake": "До 70 слов. Глубокий, психологически точный отклик ментора, объясняющий механику ступора в этой ситуации (или реакция на отмену предыдущего шага, если это retry).",
      "highlight": "До 15 слов на 'ты'. Острый, сухой диагноз уловки ума без воды для архивной карточки.",
      "action": "Одна команда. Начинается с глагола (открой, напиши, отправь, создай, выбери). Конкретный объём. До 15 минут. Без знака вопроса.",
      "emoji": "Одна эмодзи, отражающая тему действия (📄, 🏠, 📞, 🏃, 🧹 и т.п.)"
    }

    ═══ ЗАПРЕТЫ ═══
    - Не задавай вопросов.
    - Не предлагай "обсудить" или "подумать".
    - Не используй фразы поддержки ("я понимаю", "это нормально", "ты молодец").
    - Не используй кавычки вокруг значений JSON.
    - Не добавляй markdown-разметку.
    - Если в тексте несколько проблем — НЕ перечисляй их. Выбери одну и действуй.
    - Не оправдывай ситуацию пользователя ("нехватка времени", "ты устал", "это сложно").
    - Запрещено предлагать подготовительные действия (создать файл, написать заголовок, составить список, открыть папку). Только само дело: читай, пиши, решай, отправляй.
    - Тон: требовательный союзник — партнерский, сильный, требовательный, без потакания лени и жалости. Прямой, сильный, партнерский тон, побуждающий действовать прямо сейчас.

    ═══ ЧУВСТВИТЕЛЬНЫЕ ТЕМЫ: ПРИМЕРЫ ═══
    На темах денег, здоровья и отношений модель часто уходит в мягкость. Вот как НЕЛЬЗЯ и как НУЖНО:
    ❌ "Ситуация непростая, но ты справишься" → ✅ "У тебя долг и нет плана. Вот точка входа."
    ❌ "Здоровье — это важно, послушай себя" → ✅ "Ты 3 недели откладываешь поход к врачу. Запишись."
    ❌ "Отношения требуют работы с обеих сторон" → ✅ "Ты не написал ей 4 дня. Напиши конкретное сообщение из 3 предложений."

    ═══ ТЕКСТ ПОЛЬЗОВАТЕЛЯ ═══
    \(text)
    """

        if let hint = retryHint, !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += """


    ═══ СТОП. ПРЕДЫДУЩИЙ ОТВЕТ ОТКЛОНЁН ═══
    \(hint)
    Запрещено повторять структуру и угол предыдущего ответа. Не перефразируй — думай с другой точки.
    ОБЯЗАТЕЛЬНО смени тип действия:
    - Если предыдущий action был про получение (читать, смотреть, слушать, изучать) — предложи производство (написать, создать, отправить, решить, сделать).
    - Если предыдущий action был про производство — предложи получение или коммуникацию (позвонить, написать кому-то, найти, открыть и выбрать).
    Одинаковая структура, похожий глагол, тот же масштаб — это провал. Думай иначе.
    При формировании JSON поля "intake" обязательно отреагируй на отказ от предыдущего действия и покажи, как мы снижаем порог входа, чтобы обойти сопротивление.
    
    """
        }

        return prompt
    }

	// MARK: - Legacy Public API (deprecated, kept for compilation)

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
        contextSummary: String? = nil
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
            contextSummary: contextSummary
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
  Ты — Mentorio, требовательный союзник по поведенческой активации. Ты на одной стороне с пользователем против его прокрастинации, без жалости и мягкости.
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
        contextSummary: String?
	) -> String {
		return """
        OUTPUT ONLY VALID JSON. ZERO CONVERSATIONAL TEXT. NO MARKDOWN.
        
        Ты — Mentorio, требовательный союзник по поведенческой активации. Твоя задача — перевести хаос мыслей пользователя в одну конкретную физическую тактику и затем в действие на 10–15 минут.
        
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
           - Be a demanding ally: dry, direct, strong, and partner-like, but completely factual and without pity.
        
        ТЕХНИЧЕСКИЙ КОНТЕКСТ:
        — Selected Topic: \(selectedTopic ?? "null")
        — Clarifying attempts: \(clarifyingAttempts)
        — Is Fast-Track: \(isFastTrack)
        — Context Summary: \(contextSummary ?? "[Нет резюме, используй исходный текст]")
        
        ИСХОДНЫЕ ДАННЫЕ ЮЗЕРА:
        Брайндамп:
        \(text)
        
        Последний ответ:
        \(userAnswer ?? "null")
        """
	}

    // MARK: - Networking

    private static let systemPersona = "Ты — Mentorio, требовательный союзник по поведенческой активации. Ты на стороне пользователя против его прокрастинации и ступора, но без сюсюканья, жалости и мягкости (no soft coaching). Твой тон прямой, сильный, лаконичный, партнерский. Без вежливости и преамбул. Сразу к сути."

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
