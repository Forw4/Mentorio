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
    private enum MentorioIntent: String {
        case taskProcrastination = "task_procrastination"
        case decisionParalysis = "decision_paralysis"
        case preconditionsMissing = "preconditions_missing"
        case vagueOverwhelm = "vague_overwhelm"
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

    // MARK: - System Focus Prompt

    private static let focusPrompt: String = {
        let lines = [
            "OUTPUT ONLY VALID JSON. ZERO CONVERSATIONAL TEXT. NO MARKDOWN. NO EXPLANATIONS.",
            "",
            "Ты — Mentorio. Жесткий, структурный ментор. Ты не успокаиваешь, а выводишь из ступора в конкретные шаги.",
            "",
            "ГЛАВНАЯ ЦЕЛЬ:",
            "- Не философствовать, а переводить ступор в наблюдаемый прогресс.",
            "- Для разных блокеров используй разные режимы: задача, выбор, нехватка ресурса, туман/перегруз.",
            "",
            "ФОРМАТ ОБЪЕКТА (СТРОГО):",
            "{",
            "  \"topics\": null или [\"Тема 1\", \"Тема 2\", \"Тема 3\"],",
            "  \"highlight\": null или \"точная цитата из текста юзера\",",
            "  \"insight\": null или \"1-2 фактических предложения\",",
            "  \"question\": null или \"уточняющий вопрос\",",
            "  \"choices\": null или [\"Вариант 1\", \"Вариант 2\"]",
            "}",
            "",
            "ПРАВИЛА ДЛЯ choices (ОБЯЗАТЕЛЬНО):",
            "- Ровно 2 варианта.",
            "- Только физические действия во внешнем мире (написать, открыть, отправить, позвонить, создать).",
            "- Любой шаг должен завершаться АРТЕФАКТОМ: заметка, файл, сообщение, звонок, заявка, сохраненный вариант.",
            "- Для режима сложного выбора (decision_paralysis) choices должны быть проверочными и обратимыми шагами на 10-15 минут, а не финальным коммитом.",
            "- До подтверждения запрещены необратимые шаги: купить/оплатить, оформить кредит, уволиться, переехать, подписать долгий контракт.",
            "- Запрещены абстрактные когнитивные команды: подумай, проанализируй, прикинь, выбери в голове.",
            "- Запрещены действия-отмазки: отдохни, подготовься, наведи порядок, посмотри мотивацию.",
            "",
            "ПРАВИЛА ДЛЯ topics:",
            "- Каждая тема: от 2 до 4 слов, БЕЗ сложных оборотов.",
            "- Возвращай topics только когда реально 3+ независимых направлений.",
            "",
            "ПРАВИЛА ДЛЯ question:",
            "- Используй question, когда нужен один цикл уточнения/ресерча.",
            "- Если вопрос про сложный выбор, запроси только недостающие данные: 1, 2 или 3 пункта по контексту.",
            "- Если данных уже достаточно, не задавай question: сразу верни choices.",
            "- Формулируй question по-человечески, коротко и без канцелярита.",
            "- В конце question добавляй короткий CTA (6-14 слов), но не повторяй один и тот же шаблон.",
            "- Запрещено дословно повторять фразу: \"Напиши мне это сюда, и я сразу дам 2 четких варианта\".",
            "- После одного такого цикла в режиме выбора больше не задавай новых вопросов: верни choices или явный вывод о затягивании.",
            "",
            "ФОРМАТ JSON-ОТВЕТА (ОБЯЗАТЕЛЬНЫЙ):",
            "- Никакого текста до или после JSON.",
            "- Никаких пояснений, комментариев, markdown, ``` и т.п.",
            "- Только один JSON-объект, соответствующий схеме."
        ]
        return lines.joined(separator: "\n")
    }()

    // MARK: - Focus / Topics / Choices

    static func classifyIntent(
        for text: String,
        selectedTopic: String? = nil,
        userAnswer: String? = nil
    ) -> String {
        detectIntent(text: text, selectedTopic: selectedTopic, userAnswer: userAnswer).rawValue
    }

    static func isHighStakesContext(
        for text: String,
        selectedTopic: String? = nil,
        userAnswer: String? = nil
    ) -> Bool {
        let intent = detectIntent(text: text, selectedTopic: selectedTopic, userAnswer: userAnswer)
        let mergedText = [text, selectedTopic ?? "", userAnswer ?? ""]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return isHighStakesDecision(text: mergedText, intent: intent)
    }

    static func getCoreHighlightChoices(
        for text: String,
        selectedTopic: String? = nil,
        userAnswer: String? = nil,
        clarifyingAttempts: Int = 0
    ) async throws -> FocusResponse {
        // SPEC BRANCH B - SAFETY NET: Automatic transition after 3 clarifying attempts
        // "Attempt 3 — The Safety Net (attempts >= 3):"
        // "ИИ не задаёт вопрос. Принудительный переход к Mirror."
        // "Берёт точную цитату из исходного браиндампа (не придумывает)."
        if clarifyingAttempts >= 3 {
            return generateSafetyNetResponse(from: text)
        }
        
        // EXCLUSIONARY LOGIC: Each context takes absolute priority
        let prompt: String
        let intent = detectIntent(text: text, selectedTopic: selectedTopic, userAnswer: userAnswer)
        let hasUserAnswer = userAnswer?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasSelectedTopic = selectedTopic?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let highStakes = isHighStakesDecision(text: text, intent: intent)
        let decisionMissingSlots = decisionMissingInfoSlots(in: text)
        let decisionNeedsResearch = intent == .decisionParalysis && clarifyingAttempts == 0 && !hasUserAnswer && decisionMissingSlots > 0

        print("🧭 Intent route: \(intent.rawValue), attempts=\(clarifyingAttempts), highStakes=\(highStakes)")

        if hasSelectedTopic && !hasUserAnswer {
            // FOCUSED CONTEXT: user selected a topic, produce direct tactics
            prompt = """
            \(focusPrompt)

            РЕЖИМ: TASK_PROCRASTINATION (точечный фокус после выбора темы).

            Пользователь сузил фокус на теме: \(selectedTopic ?? "")

            Работай ТОЛЬКО с этой темой.
            Верни highlight, insight и choices.
            question: null.
            topics: null.

            choices должны быть физическими и завершаться артефактом.
            """
        } else {
            switch intent {
            case .decisionParalysis:
                if decisionNeedsResearch {
                    let pointsInstruction: String
                    switch decisionMissingSlots {
                    case 1:
                        pointsInstruction = "question должен запросить только 1 недостающий пункт."
                    case 2:
                        pointsInstruction = "question должен запросить только 2 недостающих пункта."
                    default:
                        pointsInstruction = "question должен запросить только 3 недостающих пункта."
                    }

                    prompt = """
                    \(focusPrompt)

                    РЕЖИМ: DECISION_PARALYSIS (сложный выбор).
                    Сейчас разрешен один адаптивный цикл ресерча, только если реально не хватает фактов.
                    Для этого кейса данных не хватает: запроси недостающие факты question-полем.

                    Контекст пользователя:
                    \(text)

                    Верни JSON только с question:
                    - topics: null
                    - highlight: null
                    - insight: null
                    - choices: null
                    - question: короткий живой запрос на недостающие факты.

                    \(pointsInstruction)
                    Вопрос должен быть прикладным и проверяемым под этот конкретный выбор.
                    Заверши вопрос одним коротким CTA и меняй формулировку между ответами.
                    Примеры CTA (выбирай и перефразируй под контекст):
                    - "Напиши это сюда, и я соберу два рабочих хода без воды"
                    - "Пришли детали сюда, и сведу выбор к двум реалистичным вариантам"
                    - "Ответь тут в 2-3 строках, и сразу перейдем к конкретике"
                    - "Скинь это сюда, и разложу решение на два понятных шага"
                    """
                } else if clarifyingAttempts == 0 && !hasUserAnswer {
                    prompt = """
                    \(focusPrompt)

                    РЕЖИМ: DECISION_PARALYSIS (сложный выбор).
                    По текущему контексту данных уже достаточно для первичного решения.
                    Не задавай question. Сразу верни:
                    - highlight
                    - insight
                    - choices (ровно 2, физические, с артефактом, без капитальных решений)
                    - question: null
                    - topics: null

                    Контекст пользователя:
                    \(text)

                    \(highStakes ? "Это high-stakes выбор. Оба choices должны снижать риск и собирать факты; покупка/оплата/финальный выбор прямо сейчас запрещены." : "")
                    """
                } else {
                    prompt = """
                    \(focusPrompt)

                    РЕЖИМ: DECISION_PARALYSIS (после одного цикла ресерча).
                    Новый цикл ресерча ЗАПРЕЩЕН. question: null.
                    Теперь обязательно выдай результат развилки:
                    - choices должны продвигать решение через проверку и фиксацию фактов,
                    - без финальной покупки/оплаты/подписания в этом шаге.

                    Контекст выбора:
                    \(text)

                    Ответ пользователя после ресерча:
                    \(userAnswer ?? "[нет ответа]")

                    Верни:
                    - highlight (точная цитата)
                    - insight (факт по результатам ресерча)
                    - choices (ровно 2, оба физические, с артефактом, реалистичные для выполнения за 10-15 минут)
                    - question: null
                    - topics: null

                    \(highStakes ? "Это high-stakes выбор. choices должны быть про снижение риска и проверку реальности, а не про немедленный коммит." : "")
                    """
                }

            case .preconditionsMissing:
                if clarifyingAttempts == 0 && !hasUserAnswer {
                    prompt = """
                    \(focusPrompt)

                    РЕЖИМ: PRECONDITIONS_MISSING.
                    Перед любыми тактиками нужна проверка мотива.

                    Контекст пользователя:
                    \(text)

                    Верни JSON только с question:
                    - topics: null
                    - highlight: null
                    - insight: null
                    - choices: null
                    - question: "Ты реально не можешь начать без этого ресурса, или это легальный способ не работать сегодня?"
                    """
                } else {
                    prompt = """
                    \(focusPrompt)

                    РЕЖИМ: PRECONDITIONS_MISSING (после проверки мотива).

                    Контекст пользователя:
                    \(text)

                    Ответ на проверку:
                    \(userAnswer ?? "[нет ответа]")

                    Правило:
                    - Если ресурс реально нужен: choices направь на получение ресурса (сравнить, накопить, занять, найти альтернативу).
                    - Если это избегание: choices направь на прямой прогресс по задаче без покупки.

                    Верни:
                    - highlight
                    - insight
                    - choices (ровно 2, физические, с артефактом)
                    - question: null
                    - topics: null
                    """
                }

            case .vagueOverwhelm:
                if clarifyingAttempts == 0 && !hasUserAnswer {
                    prompt = """
                    \(focusPrompt)

                    РЕЖИМ: VAGUE_OVERWHELM.
                    Текст эмоциональный и расплывчатый.
                    Верни ТОЛЬКО один уточняющий вопрос (question), чтобы вытащить конкретную сферу.
                    Остальные поля null.

                    Текст пользователя:
                    \(text)
                    """
                } else {
                    prompt = """
                    \(focusPrompt)

                    РЕЖИМ: TASK_PROCRASTINATION после уточнения.

                    Исходный текст:
                    \(text)

                    Уточнение пользователя:
                    \(userAnswer ?? "")

                    Верни highlight, insight, choices.
                    question: null.
                    topics: null.
                    choices только физические и с артефактом.
                    """
                }

            case .taskProcrastination:
                if hasUserAnswer {
                    prompt = """
                    \(focusPrompt)

                    РЕЖИМ: TASK_PROCRASTINATION.

                    Пользователь ответил на уточняющий вопрос:
                    \(userAnswer ?? "")

                    Анализируй ТОЛЬКО этот ответ.
                    Верни highlight, insight, choices.
                    question: null.
                    topics: null.
                    choices только физические и с артефактом.
                    """
                } else {
                    prompt = """
                    \(focusPrompt)

                    РЕЖИМ: TASK_PROCRASTINATION.

                    Текст пользователя:
                    \(text)

                    Если в тексте 3+ независимых направлений, верни topics.
                    Иначе верни highlight, insight, choices.
                    choices: ровно 2, физические, с артефактом.
                    """
                }
            }
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

        let cleaned = try cleanJSONText(rawText)  // ← Now properly throws on invalid JSON
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw MentorioAIError.invalidResponse
        }

        do {
            let response = try JSONDecoder().decode(FocusResponse.self, from: jsonData)
            let normalizedResponse = normalizeResponse(
                response,
                intent: intent,
                sourceText: text,
                userAnswer: userAnswer,
                clarifyingAttempts: clarifyingAttempts,
                highStakes: highStakes
            )
            
            // VALIDATION: Ensure response is not incomplete
            // If topics and choices are both empty, question MUST be non-empty
            let hasTopics = normalizedResponse.topics?.isEmpty == false
            let hasChoices = normalizedResponse.choices?.isEmpty == false
            let hasQuestion = normalizedResponse.question?.isEmpty == false
            
            if !hasTopics && !hasChoices && !hasQuestion {
                print("❌ INCOMPLETE RESPONSE: No topics, choices, or question returned")
                print("Response: \(normalizedResponse)")
                throw MentorioAIError.incompleteResponse
            }
            
            return normalizedResponse
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
        let inferredIntent = detectIntent(text: braindump)
        let highStakes = isHighStakesDecision(text: "\(braindump) \(choice) \(insight)", intent: inferredIntent)

        let prompt = """
        Ты — Mentorio, прямой и приземленный ментор по поведенческой активации.
        Твоя задача: не драматизировать, а давать выполнимый следующий шаг.

        Контекст пользователя:
        — Брайндамп: \(braindump)
        — Ключевая фраза (highlight): \(highlight)
        — Фактическая ситуация (insight): \(insight)
        — Выбранная тактика (choice): \(choice)

        МИССИЯ:
        Сформулируй ОДНО конкретное физическое действие, которое реалистично продвинет выбранную тактику "\(choice)".
        Действие должно быть связано с реальной задачей (музыка, FL Studio, учеба, поиск квартиры, сербский язык, работа и т.п.).
        Это должен быть следующий шаг, а не капитальный жизненный коммит.

        ОБЯЗАТЕЛЬНОЕ ПРАВИЛО АРТЕФАКТА:
        - Действие валидно только если оставляет наблюдаемый артефакт во внешнем мире: заметка, файл, сообщение, заявка, звонок, сохраненный вариант.
        - Команда без артефакта запрещена.

        \(highStakes ? "HIGH-STAKES MODE ВКЛЮЧЕН: это чувствительное решение. Первое действие должно снижать риск и уточнять факты (таблица критериев, проверка ограничений, короткий pre-mortem), но не фиксировать финальный коммит." : "")

        ЖЕСТКИЕ ОГРАНИЧЕНИЯ:
        - Время выполнения: обычно 10-15 минут, максимум 20 минут прямо сейчас.
        - Действие должно начинаться с глагола прямого действия: открой, нажми, запиши, вставь, запусти, отправь, позвони, найди, создай.
        - Запрещены глаголы размышления: подумай, реши, осознай, проанализируй, выбери, прикинь.
        - Запрещены подготовительные действия: наведи порядок, убери стол, напиши план, поставь таймер, настрой пространство, посмотри мотивационное видео.
        - Запрещены действия-отмазки: отдохни, переключись, прогуляйся, посмотри серию, полежи, поешь.
        - Запрещены размытые команды: начни работать, займись делом, перестань лениться, обратись за помощью.
        - Запрещены капитальные коммиты в первом шаге: купить, оплатить, оформить кредит, подписать договор, уволиться, переехать.

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

        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitizeOneAction(cleaned, intent: inferredIntent, highStakes: highStakes)
    }

    // MARK: - Networking

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

    // MARK: - JSON Cleaning

    private static func cleanJSONText(_ raw: String) throws -> String {
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
        } else {
            // CRITICAL: No JSON braces found - this is a hard failure!
            // Prevent silent corruption of state machine
            print("❌ CRITICAL JSON PARSING ERROR: No JSON braces found in API response")
            print("Raw response preview: \(raw.prefix(200))")
            throw MentorioAIError.invalidJSONResponse
        }
        
        // Additional validation: Reject empty JSON or whitespace-only JSON
        if text == "{}" || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("❌ CRITICAL JSON VALIDATION ERROR: Response is empty JSON or whitespace")
            print("Raw response preview: \(raw.prefix(200))")
            throw MentorioAIError.invalidJSONResponse
        }

        return text
    }
    
    // MARK: - Vague Input Detection

    private static func normalizeResponse(
        _ response: FocusResponse,
        intent: MentorioIntent,
        sourceText: String,
        userAnswer: String?,
        clarifyingAttempts: Int,
        highStakes: Bool
    ) -> FocusResponse {
        var normalized = response

        // Global safeguard: if model returns too many choices, keep exactly two.
        if let choices = normalized.choices, choices.count > 2 {
            normalized = FocusResponse(
                topics: normalized.topics,
                highlight: normalized.highlight,
                insight: normalized.insight,
                question: normalized.question,
                choices: Array(choices.prefix(2))
            )
        }

        if let question = normalized.question,
           !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized = FocusResponse(
                topics: normalized.topics,
                highlight: normalized.highlight,
                insight: normalized.insight,
                question: normalizeQuestionCTA(question, seedText: sourceText),
                choices: normalized.choices
            )
        }

        // Decision rule: after one research cycle we must not ask another question.
        if intent == .decisionParalysis && clarifyingAttempts >= 1 {
            let hasChoices = normalized.choices?.isEmpty == false

            if !hasChoices {
                let fallbackHighlight = normalized.highlight ?? extractFirstMeaningfulSentence(from: sourceText)
                let fallbackInsight = normalized.insight ?? "Ресерч-цикл завершен. Нужно зафиксировать решение или признать, что цель сейчас не приоритет."

                let fallbackChoices: [String]
                if highStakes {
                    fallbackChoices = [
                        "Открой заметки и за 10 минут заполни таблицу 3 критериев для обоих вариантов и сохрани промежуточного лидера",
                        "Открой браузер и сохрани 2 независимых обзора по твоему сценарию использования, затем выпиши 3 ограничения в заметку"
                    ]
                } else {
                    fallbackChoices = [
                        "Открой заметки и за 10 минут сравни 2 варианта по цене, задаче и рискам, затем зафиксируй текущего лидера",
                        "Открой мессенджер и отправь 1 уточняющий вопрос человеку с опытом, затем сохрани ответ в заметку"
                    ]
                }

                return FocusResponse(
                    topics: nil,
                    highlight: fallbackHighlight,
                    insight: fallbackInsight,
                    question: nil,
                    choices: fallbackChoices
                )
            }

            return FocusResponse(
                topics: nil,
                highlight: normalized.highlight,
                insight: normalized.insight,
                question: nil,
                choices: normalized.choices
            )
        }

        // Preconditions rule: after check, prioritize concrete resource-acquisition actions.
        if intent == .preconditionsMissing && clarifyingAttempts >= 1 {
            let hasChoices = normalized.choices?.isEmpty == false

            if !hasChoices {
                let fallbackHighlight = normalized.highlight ?? extractFirstMeaningfulSentence(from: sourceText)
                let answerText = userAnswer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let looksLikeRealBlocker = answerText.contains("реально") || answerText.contains("нужен") || answerText.contains("без")

                let fallbackInsight: String
                let fallbackChoices: [String]
                if looksLikeRealBlocker {
                    fallbackInsight = "Ресурс похож на реальный блокер. Нужны шаги на его получение, а не имитация работы без условий."
                    fallbackChoices = [
                        "Открой заметки и сравни 2 доступных варианта ресурса по цене и сроку сегодня",
                        "Открой мессенджер и отправь одно сообщение о займе/аренде нужного ресурса"
                    ]
                } else {
                    fallbackInsight = "Покупка выглядит как откладывание. Лучше дать минимальный ход по самой задаче уже сегодня."
                    fallbackChoices = [
                        "Открой заметки и зафиксируй один шаг по задаче, который можно сделать без покупки",
                        "Открой рабочий инструмент и сохрани один минимальный результат в файл"
                    ]
                }

                return FocusResponse(
                    topics: nil,
                    highlight: fallbackHighlight,
                    insight: fallbackInsight,
                    question: nil,
                    choices: fallbackChoices
                )
            }

            return FocusResponse(
                topics: nil,
                highlight: normalized.highlight,
                insight: normalized.insight,
                question: nil,
                choices: normalized.choices
            )
        }

        return normalized
    }

    private static func normalizeQuestionCTA(_ question: String, seedText: String) -> String {
        let banned = "напиши мне это сюда, и я сразу дам 2 четких варианта"
        var cleaned = question.trimmingCharacters(in: .whitespacesAndNewlines)

        let lower = cleaned.lowercased()
        if let range = lower.range(of: banned) {
            let distance = lower.distance(from: lower.startIndex, to: range.lowerBound)
            let end = cleaned.index(cleaned.startIndex, offsetBy: distance)
            cleaned = cleaned[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let ctaOptions = [
            "Напиши это сюда, и я соберу два рабочих хода без воды",
            "Пришли детали сюда, и сведу выбор к двум реалистичным вариантам",
            "Ответь тут в 2-3 строках, и сразу перейдем к конкретике",
            "Скинь это сюда, и разложу решение на два понятных шага",
            "Напиши сюда как есть, и дам короткую развилку на сейчас",
            "Пришли факты сюда, и отсечем лишнее в два хода"
        ]

        let hasCTA = ["напиши", "пришли", "скинь", "ответь"]
            .contains { lower.contains($0) }
        if hasCTA {
            return cleaned
        }

        let seed = abs(seedText.hashValue)
        let suffix = ctaOptions[seed % ctaOptions.count]
        let separator = cleaned.hasSuffix("?") ? " " : ". "
        return "\(cleaned)\(separator)\(suffix)"
    }

    private static func decisionMissingInfoSlots(in text: String) -> Int {
        let lower = text.lowercased()
        var missing = 0

        if !containsBudgetInfo(in: lower) {
            missing += 1
        }

        if !containsDeadlineInfo(in: lower) {
            missing += 1
        }

        if !containsCriticalNeedsInfo(in: lower) {
            missing += 1
        }

        return min(3, max(0, missing))
    }

    private static func containsBudgetInfo(in text: String) -> Bool {
        let budgetMarkers = ["бюджет", "цена", "стоим", "доллар", "usd", "$", "руб", "eur", "€"]
        if budgetMarkers.contains(where: { text.contains($0) }) {
            return true
        }

        let regex = try? NSRegularExpression(pattern: #"\b[0-9]{3,6}\b"#)
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let hasNumber = regex?.firstMatch(in: text, options: [], range: nsRange) != nil
        return hasNumber
    }

    private static func containsDeadlineInfo(in text: String) -> Bool {
        let markers = ["дедлайн", "срок", "когда", "до ", "к ", "сегодня", "завтра", "недел", "месяц", "дата"]
        return markers.contains(where: { text.contains($0) })
    }

    private static func containsCriticalNeedsInfo(in text: String) -> Bool {
        let markers = [
            "задач", "workflow", "монтаж", "рендер", "прилож", "программ", "софт", "плагин",
            "final cut", "davinci", "logic", "codec", "кодек"
        ]
        return markers.contains(where: { text.contains($0) })
    }

    private static func detectIntent(
        text: String,
        selectedTopic: String? = nil,
        userAnswer: String? = nil
    ) -> MentorioIntent {
        let merged = [text, selectedTopic ?? "", userAnswer ?? ""]
            .joined(separator: " ")
            .lowercased()

        if isDecisionInput(merged) {
            return .decisionParalysis
        }

        if isPreconditionsMissingInput(merged) {
            return .preconditionsMissing
        }

        if isVagueInput(text) {
            return .vagueOverwhelm
        }

        return .taskProcrastination
    }

    private static func isDecisionInput(_ text: String) -> Bool {
        let strongMarkers = [
            "выбрать", "выбор", "что лучше", "стоит ли", "между", "сравнить",
            "ipad", "macbook", "ноутбук", "покупать", "купить"
        ]

        if strongMarkers.contains(where: { text.contains($0) }) {
            return true
        }

        let weakMarkers = ["или", "вариант", "решение"]
        let weakHits = weakMarkers.filter { text.contains($0) }.count
        return weakHits >= 2
    }

    private static func isPreconditionsMissingInput(_ text: String) -> Bool {
        let markers = [
            "не могу начать без", "без этого не могу", "нет денег", "нет бюджета", "нет ресурса",
            "сначала купить", "пока не куплю", "нет айпада", "нет ноутбука", "нужен макбук",
            "нет софта", "нет доступа", "нечем"
        ]

        return markers.contains(where: { text.contains($0) })
    }

    private static func isHighStakesDecision(text: String, intent: MentorioIntent) -> Bool {
        guard intent == .decisionParalysis || intent == .preconditionsMissing else {
            return false
        }

        let lower = text.lowercased()
        let lifeChangingMarkers = [
            "переезд", "эмиграц", "релокац", "брак", "развод",
            "карьера", "смена работы", "увольн", "ипотек", "ребенок"
        ]

        if lifeChangingMarkers.contains(where: { lower.contains($0) }) {
            return true
        }

        let pattern = #"(?:\$\s*([0-9]{3,6})|([0-9]{3,6})\s*(usd|доллар|долларов|eur|euro|€|₽|руб))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }

        let nsRange = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        let matches = regex.matches(in: lower, options: [], range: nsRange)

        for match in matches {
            if match.numberOfRanges >= 3 {
                var numberText: String?
                var unitText: String?
                var hasDollarPrefix = false

                if let range1 = Range(match.range(at: 1), in: lower), !range1.isEmpty {
                    numberText = String(lower[range1])
                    hasDollarPrefix = true
                } else if let range2 = Range(match.range(at: 2), in: lower), !range2.isEmpty {
                    numberText = String(lower[range2])
                }

                if match.numberOfRanges >= 4,
                   let range3 = Range(match.range(at: 3), in: lower),
                   !range3.isEmpty {
                    unitText = String(lower[range3])
                }

                if let numberText,
                   let amount = Int(numberText) {
                    let unit = (unitText ?? "").lowercased()
                    let threshold: Int

                    if unit.contains("руб") || unit.contains("₽") {
                        threshold = 150_000
                    } else if unit.contains("usd") || unit.contains("доллар") || unit.contains("eur") || unit.contains("euro") || unit.contains("€") || hasDollarPrefix {
                        threshold = 1_500
                    } else {
                        threshold = 2_000
                    }

                    if amount >= threshold {
                        return true
                    }
                }
            }
        }

        return false
    }

    private static func sanitizeOneAction(_ action: String, intent: MentorioIntent, highStakes: Bool) -> String {
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Открой заметки и за 10 минут запиши один следующий шаг с наблюдаемым результатом по выбранной тактике"
        }

        guard intent == .decisionParalysis || highStakes else {
            return trimmed
        }

        let lower = trimmed.lowercased()
        let forbiddenCommitMarkers = [
            "купи", "купить", "оплати", "оплатить", "закажи", "заказать",
            "оформи кредит", "подпиши", "подписать", "уволь", "переез", "финальн"
        ]

        if forbiddenCommitMarkers.contains(where: { lower.contains($0) }) {
            return "Открой заметки и за 10 минут сравни оба варианта по 3 критериям (цена, ключевая задача, риски) и зафиксируй текущего лидера одной строкой"
        }

        return trimmed
    }
    
    /// Detects if input is vague (emotional, no clear topics or structure)
    private static func isVagueInput(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let trimmed = lowercased.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Too short likely means vague
        if trimmed.count < 20 {
            return true
        }
        
        // Simple heuristics for vague input:
        // - Few clear nouns or topics
        // - Lots of emotional words
        // - Questions without concrete content
        let vagueMarkers = ["как дела", "что делать", "не знаю", "хм", "ugh", "argh", "блин", "бля"]
        let hasVagueMarker = vagueMarkers.contains { marker in
            trimmed.contains(marker)
        }
        
        if hasVagueMarker {
            return true
        }
        
        // Count potential topics (words that might indicate a specific domain)
        let topicKeywords = [
            "музыка", "fl studio", "биты", "beats",
            "работа", "работы", "job",
            "квартира", "apt", "жилье",
            "язык", "language", "english", "spanish",
            "учеба", "учебе", "study",
            "проект", "project",
            "творчество", "creative",
            "отношения", "relationships",
            "деньги", "money"
        ]
        
        let topicCount = topicKeywords.filter { keyword in
            trimmed.contains(keyword)
        }.count
        
        // If very few concrete topics, likely vague
        return topicCount == 0
    }
    
    // MARK: - Safety Net Response Generator (Branch B, Attempt 3+)
    
    private static func generateSafetyNetResponse(from braindump: String) -> FocusResponse {
        // SPEC: "Attempt 3 — The Safety Net (attempts >= 3):"
        // Extract exact quote from braindump (first meaningful sentence)
        let highlight = extractFirstMeaningfulSentence(from: braindump)
        
        // Generate insight for safety net
        let insight = "Похоже, фокус все еще плывет. Берем одну цитату и двигаемся через внешний артефакт, без размышлений в голове."
        
        // Provide maximally simple choices per spec
        let choices = [
            "Открой заметки и выпиши 3 факта, что именно стопорит задачу",
            "Отправь одно сообщение человеку, который может сдвинуть эту задачу сегодня",
            "Открой рабочий проект и сохрани один минимальный результат в файл"
        ]
        
        return FocusResponse(
            topics: nil,
            highlight: highlight,
            insight: insight,
            question: nil,  // No question at attempt 3
            choices: Array(choices.prefix(2))  // Return exactly 2 choices per spec
        )
    }
    
    private static func extractFirstMeaningfulSentence(from text: String) -> String {
        let sentences = text.split(separator: ".", omittingEmptySubsequences: true)
        
        // Find first sentence with meaningful length (> 10 chars)
        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespaces)
            if trimmed.count > 10 {
                return String(trimmed)
            }
        }
        
        // Fallback: return first 50 chars if no full sentence found
        return String(text.prefix(50)).trimmingCharacters(in: .whitespaces)
    }
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
