//
//  MentorioAIService.swift
//  Mentorio
//

import Foundation

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
    static var apiKey: String {
        guard let key = Bundle.main.infoDictionary?["OPENROUTER_API_KEY"] as? String,
              !key.isEmpty else {
            fatalError("🚨 API Key not found! Убедись, что добавил OPENROUTER_API_KEY в Info.plist")
        }
        return key
    }

    private static let endpoint = "https://openrouter.ai/api/v1/chat/completions"
    private static let model = "google/gemini-2.0-flash-001"

    // MARK: - System Focus Prompt

    private static let focusPrompt: String = {
        let lines = [
            "Ты — Mentorio. Жесткий ментор. Без эмпатии, без поддержки, без общих фраз. Ты не утешаешь, ты пинаешь в действие.",
            "",
            "ГЛАВНАЯ ЦЕЛЬ:",
            "- Не планировать жизнь, а ПРЕРЫВАТЬ ступор и прокрастинацию ЗДЕСЬ И СЕЙЧАС.",
            "- Ты не предлагаешь отдых, паузы, подготовку или самоанализ. Только атака на конкретное дело.",
            "",
            "ВАЖНАЯ ЛОГИКА:",
            "1. Если текст затрагивает 3+ разные темы (например: Белград, биты, сериалы, отношения) — вернёшь ответ с МАССИВОМ topics.",
            "2. Если текст фокусируется на одной-двух конкретных темах — вернёшь highlight, insight и choices. question ВСЕГДА null.",
            "",
            "Возвращай ТОЛЬКО VALID JSON без markdown и без лишнего текста:",
            "{",
            "  \"topics\": null или [\"Тема 1\", \"Тема 2\", \"Тема 3\"],",
            "  \"highlight\": null или \"точная цитата из текста юзера\",",
            "  \"insight\": null или \"1-2 предложения сути. Без советов, без обобщений, без эмпатии.\",",
            "  \"question\": null,",
            "  \"choices\": null или [\"Вариант 1\", \"Вариант 2\"]",
            "}",
            "",
            "ЕСЛИ ВОЗВРАЩАЕШЬ topics:",
            "- Каждая тема: от 2 до 4 слов, БЕЗ сложных оборотов.",
            "- Примеры хорошего: \"Музыка и биты\", \"Жилищный вопрос\", \"Страх общения\".",
            "- Примеры плохого: \"Как найти баланс между творчеством и монетизацией\".",
            "",
            "ЕСЛИ ВОЗВРАЩАЕШЬ highlight/insight/choices:",
            "- highlight: точная цитата из текста юзера (самая жесткая и важная мысль).",
            "- insight: 1–2 предложения фактического положения. Без советов, без обобщений, без подбадриваний.",
            "- question: ВСЕГДА null.",
            "- choices: ровно 2 БОЕВЫЕ ТАКТИКИ, направленные на КОНКРЕТНОЕ НУЖНОЕ ДЕЛО (FL Studio, поиск квартиры, сербский, учеба, работа, конкретный проект).",
            "",
            "ЖЕСТКОЕ ПРАВИЛО ДЛЯ choices:",
            "- Тактики — это мини-стратегии атаки на конкретную задачу, а не размышления и не забота о себе.",
            "- Каждая тактика должна вести к конкретному физическому действию в нужной сфере: открыть FL Studio и сделать шаг по треку, открыть сайт с квартирами и сделать действие, открыть приложение для сербского и сделать шаг.",
            "",
            "Примеры ХОРОШЕГО (АТАКА):",
            "  Для \"хочу делать биты во FL Studio, но туплю\":",
            "  - \"Открыть FL Studio и собрать один паттерн из 4 ударов\"",
            "  - \"Открыть последний проект во FL Studio и изменить один звук в драм-партии\"",
            "",
            "  Для \"ищу квартиру в Белграде, но откладываю\":",
            "  - \"Открыть Halo Oglasi и добавить одну квартиру в избранное\"",
            "  - \"Открыть WhatsApp и отправить одно сообщение агенту по недвижимости\"",
            "",
            "  Для \"не могу выучить сербский\":",
            "  - \"Открыть Duolingo и пройти один конкретный урок\"",
            "  - \"Открыть YouTube и включить первые 5 минут одного сербского видео\"",
            "",
            "Примеры ПЛОХОГО (ЗАПРЕЩЕНО НАВСЕГДА):",
            "  ❌ \"Найти баланс между работой и отдыхом\"",
            "  ❌ \"Разобраться в себе\"",
            "  ❌ \"Принять свое состояние\"",
            "  ❌ \"Проработать установку\"",
            "  ❌ \"Подумать, чего ты хочешь\"",
            "  ❌ \"Сделать уборку\" (если это не прямая часть задачи, типа разобрать конкретный пакет документов по учебе)",
            "  ❌ \"Отдохнуть, переключиться, посмотреть сериал, полежать\"",
            "  ❌ \"Поставить таймер, написать план, подготовиться\"",
            "",
            "АНТИ-ПРОКРАСТИНАЦИОННОЕ ПРАВИЛО:",
            "- Категорически запрещены «подготовительные» действия: убрать стол, сделать план, настроить рабочее место, поставить таймер, посмотреть мотивационное видео.",
            "- Есть только одно направление: прямо сейчас ударить по задаче.",
            "",
            "ФОРМАТ JSON-ОТВЕТА (ОБЯЗАТЕЛЬНЫЙ):",
            "- Никакого текста до или после JSON.",
            "- Никаких пояснений, комментариев, markdown, ``` и т.п.",
            "- Только один JSON-объект, соответствующий схеме."
        ]
        return lines.joined(separator: "\n")
    }()

    // MARK: - Focus / Topics / Choices

    static func getCoreHighlightChoices(
        for text: String,
        selectedTopic: String? = nil,
        userAnswer: String? = nil
    ) async throws -> FocusResponse {
        // EXCLUSIONARY LOGIC: Each context takes absolute priority
        let prompt: String

        if let userAnswer = userAnswer,
           !userAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // ABSOLUTE FOCUS: Only the user's answer, ignore braindump completely
            prompt = """
            \(focusPrompt)

            Пользователь ответил на уточняющий вопрос:
            \(userAnswer)

            Анализируй ТОЛЬКО этот ответ. Игнорируй исходный брайндамп.
            Верни:
            - highlight (точная цитата из ответа),
            - insight (фактическое положение без советов и без поддержки),
            - choices (ровно две боевые тактики атаки на КОНКРЕТНОЕ дело из ответа).

            question ВСЕГДА null.
            topics ВСЕГДА null.
            Никаких советов по психологии, отдыху, планированию, уборке или рефлексии.
            """
        } else if
            let selectedTopic = selectedTopic,
            !selectedTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // FOCUSED CONTEXT: Only the selected topic
            prompt = """
            \(focusPrompt)

            Пользователь сузил фокус на теме: \(selectedTopic)

            Работай ТОЛЬКО с этой темой.
            Верни highlight, insight и choices только для этой темы.
            question ВСЕГДА null.
            topics ВСЕГДА null.
            Любая тактика в choices должна вести к прямому действию в этой теме (музыка, учеба, работа, квартира, язык и т.д.), а не к уборке, отдыху, самоанализу или планированию.
            """
        } else {
            // DEFAULT: General braindump
            prompt = """
            \(focusPrompt)

            Текст пользователя:
            \(text)
            """
        }

        let body = ChatRequest(
            model: model,
            messages: [ChatRequest.ChatMessage(role: "user", content: prompt)]
        )

        let requestData = try JSONEncoder().encode(body)
        let responseData = try await postToOpenRouter(requestBody: requestData)

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: responseData)
        guard let rawText = decoded.choices.first?.message.content,
              !rawText.isEmpty else {
            throw MentorioAIError.emptyResponse
        }

        print("RAW API RESPONSE: \(rawText)")

        let cleaned = cleanJSONText(rawText)
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw MentorioAIError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(FocusResponse.self, from: jsonData)
        } catch {
            print("DECODING ERROR: \(error)")
            print("CLEANED JSON: \(cleaned)")
            throw error
        }
    }

    // MARK: - One Action

    static func getOneAction(
        for choice: String,
        braindump: String,
        highlight: String,
        insight: String
    ) async throws -> String {
        let prompt = """
        Ты — Mentorio, жесткий ментор по поведенческой активации (Behavioural Activation).
        Ты работаешь с Никитой, 20 лет, студент EKOF. Он не хочет эмпатии. Он хочет пинок.

        Контекст пользователя:
        — Брайндамп: \(braindump)
        — Ключевая фраза (highlight): \(highlight)
        — Фактическая ситуация (insight): \(insight)
        — Выбранная тактика (choice): \(choice)

        МИССИЯ:
        Сформулируй ОДНО конкретное физическое действие, которое ЖЕСТКО реализует выбранную тактику "\(choice)".
        Действие должно быть связано с реальной задачей (музыка, FL Studio, учеба, поиск квартиры, сербский язык, работа и т.п.).
        Никакой уборки, отдыха, планирования, рефлексии, подготовки или \"разогрева\".

        ЖЕСТКИЕ ОГРАНИЧЕНИЯ:
        - Время выполнения ≤ 2 минут прямо сейчас.
        - Действие должно начинаться с глагола прямого действия: открой, нажми, запиши, вставь, запусти, отправь, позвони, найди, создай.
        - Запрещены глаголы размышления: подумай, реши, осознай, проанализируй, выбери, прикинь.
        - Запрещены подготовительные действия: наведи порядок, убери стол, напиши план, поставь таймер, настрой пространство, посмотри мотивационное видео.
        - Запрещены действия-отмазки: отдохни, переключись, прогуляйся, посмотри серию, полежи, поешь.
        - Запрещены размытые команды: начни работать, займись делом, перестань лениться, обратись за помощью.

        ПРАВИЛА КОНКРЕТНОСТИ:
        1. Обязательно укажи конкретный инструмент, приложение, сайт или предмет (например: FL Studio, Duolingo, YouTube, Halo Oglasi, WhatsApp, Telegram, блокнот, заметки на телефоне).
        2. У действия должен быть наблюдаемый результат: вкладка открыта, проект открыт, сообщение написано, кнопка нажата, файл создан.
        3. Если действие связано с общением, ОБЯЗАТЕЛЬНО дай готовый текст сообщения по шаблону, без \"своими словами\".

        ПРАВИЛО СООБЩЕНИЙ (ВАЖНО):
        - Если из тактики логично следует общение (написать другу, преподу, работодателю, агенту и т.п.), ты обязан дать точный текст сообщения.
        - Формат: Сначала глагол, потом канал, потом текст.
        - Пример правильного формата:
          \"Открой WhatsApp и отправь сообщение: 'Эй, можешь сегодня созвониться на 10 минут, чтобы я показал свой бит и получил честный фидбек?'\".
        - Нельзя писать: \"Напиши другу сообщение\", \"Сформулируй запрос\", \"Напиши что-то честное\".

        ВЕКТОР ПРОГРЕССА:
        - Действие должно бить прямо в цель: FL Studio → открыть проект / сделать паттерн; сербский → открыть урок / повторить фразы; квартира → открыть сайт / написать агенту; учеба → открыть конретную тему / задать вопрос преподу.
        - Действие не должно улучшать жизнь \"в общем\", оно должно двигать вперёд КОНКРЕТНУЮ задачу из контекста.

        ФОРМАТ ОТВЕТА:
        - Ответь ОДНОЙ строкой с командой действия.
        - Без кавычек, без точки в конце, без пояснений, без нумерации.
        - Никаких дополнительных предложений, мотивации или объяснений. Только чистая команда.

        СЕЙЧАС СФОРМУЛИРУЙ ЭТУ КОМАНДУ.
        """

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

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Networking

    private static func postToOpenRouter(requestBody: Data) async throws -> Data {
        guard let url = URL(string: endpoint) else {
            throw MentorioAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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

    // MARK: - JSON Cleaning

    private static func cleanJSONText(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code fences if модель всё-таки вернула ```json ... ```
        if text.hasPrefix("```") {
            if let firstFenceRange = text.range(of: "```"),
               let lastFenceRange = text.range(of: "```", options: .backwards),
               firstFenceRange.lowerBound != lastFenceRange.lowerBound {
                let start = text.index(after: firstFenceRange.upperBound)
                let inner = text[start..<lastFenceRange.lowerBound]
                text = String(inner).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Иногда модель добавляет префиксы/суффиксы вроде "Вот JSON:" — отрезаем до первого '{' и после последнего '}'
        if let firstBrace = text.firstIndex(of: "{"),
           let lastBrace = text.lastIndex(of: "}") {
            text = String(text[firstBrace...lastBrace])
        }

        return text
    }
}

// MARK: - Error Type

enum MentorioAIError: Error {
    case invalidURL
    case invalidResponse
    case emptyResponse
}
