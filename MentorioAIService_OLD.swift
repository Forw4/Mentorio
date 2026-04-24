//
//  MentorioAIService.swift
//  Mentorio
//

#if false

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
            "- После одного цикла уточнения в режиме выбора question: null (обязательно).",
            "- Верни highlight, insight и choices (ровно 2).",
            "- Если данных все еще мало, кратко зафиксируй это в insight, но choices все равно выдай как проверочные шаги на 10-15 минут.",
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
        // Hard multi-topic gate: for initial braindump with 3+ independent themes,
        // force topic selection before question/choices.
        let topicRanking = rankedTopicCategories(in: text)
        logTopicRoutingTrace(
            source: text,
            selectedTopic: selectedTopic,
            userAnswer: userAnswer,
            clarifyingAttempts: clarifyingAttempts,
            rankedTopics: topicRanking
        )

        if shouldForceTopicSelection(
            text: text,
            selectedTopic: selectedTopic,
            userAnswer: userAnswer,
            clarifyingAttempts: clarifyingAttempts
        ) {
            return FocusResponse(
                topics: extractForcedTopics(from: text),
                highlight: nil,
                insight: nil,
                question: nil,
                choices: nil
            )
        }

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
            Не расширяй тему и не подменяй её соседним доменом.
            Не уводи в абстрактную мотивацию и общие советы.
            Верни highlight, insight и choices.
            question: null.
            topics: null.

            choices должны быть физическими и завершаться артефактом.
            Каждый choice должен явно опираться на слова и объекты из выбранной темы.
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
                selectedTopic: selectedTopic,
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
        insight: String,
        selectedTopic: String? = nil
    ) async throws -> String {
        let inferredIntent = detectIntent(text: braindump)
        let highStakes = isHighStakesDecision(text: "\(braindump) \(choice) \(insight)", intent: inferredIntent)
        let selectedFocus = selectedTopic?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceContext = extractOneActionSourceContext(
            from: braindump,
            highlight: highlight,
            insight: insight,
            choice: choice,
            selectedTopic: selectedFocus
        )
        let strictFocus = selectedFocus?.isEmpty == false ? selectedFocus! : choice

        let prompt = """
        Ты — Mentorio, прямой и приземленный ментор по поведенческой активации.
        Твоя задача: не драматизировать, а давать выполнимый следующий шаг.

        Контекст пользователя:
        — Брайндамп: \(braindump)
        — Ключевая фраза (highlight): \(highlight)
        — Фактическая ситуация (insight): \(insight)
        — Выбранная тактика (choice): \(choice)
        — Выбранный фокус (selected_topic): \(selectedFocus ?? "[не выбран]")
        — Ядро для действия (source_context): \(sourceContext)

        МИССИЯ:
        Сформулируй ОДНО конкретное физическое действие, которое реалистично продвинет выбранную тактику "\(choice)".
        Приоритет контекста строго такой:
        1) selected_topic (если есть) и choice — главный ориентир.
        2) braindump (полный исходный контекст) — ограничения и факты.
        3) source_context и insight — уточнение деталей.
        Если есть конфликт, следуй выбранному фокусу и choice.
        Запрещено уводить действие в соседний домен.
        В этой задаче жесткий якорь: "\(strictFocus)".
        Действие должно быть связано с реальной задачей пользователя и занимать 10-20 минут.
        Это следующий шаг прямо сейчас, а не капитальный жизненный коммит.

        ОБЯЗАТЕЛЬНОЕ ПРАВИЛО АРТЕФАКТА:
        - Действие валидно только если оставляет наблюдаемый артефакт во внешнем мире: заметка, файл, сообщение, заявка, звонок, сохраненный вариант.
        - Команда без артефакта запрещена.

        \(highStakes ? "HIGH-STAKES MODE ВКЛЮЧЕН: это чувствительное решение. Первое действие должно снижать риск и уточнять факты (таблица критериев, проверка ограничений, короткий pre-mortem), но не фиксировать финальный коммит." : "")

        ЖЕСТКИЕ ОГРАНИЧЕНИЯ:
        - Время выполнения: обычно 10-15 минут, максимум 20 минут прямо сейчас.
        - Действие должно начинаться с глагола прямого действия: открой, нажми, запиши, вставь, запусти, отправь, позвони, найди, создай.
        - Запрещены глаголы размышления: подумай, реши, осознай, проанализируй, выбери, прикинь.
        - Запрещены подготовительные/отвлекающие шаги и отмазки: наведи порядок, убери стол, поставь таймер, отдохни, переключись, посмотри мотивацию.
        - Запрещены размытые команды: начни работать, займись делом, обратись за помощью.
        - Запрещены капитальные коммиты в первом шаге: купить, оплатить, оформить кредит, подписать договор, уволиться, переехать.

        ПРАВИЛА КОНКРЕТНОСТИ:
        1. Обязательно укажи конкретный инструмент, приложение, сайт, документ или канал связи из контекста задачи.
        2. У действия должен быть наблюдаемый результат: вкладка открыта, проект открыт, сообщение написано, кнопка нажата, файл создан.
                3. Если действие связано с общением, ОБЯЗАТЕЛЬНО дай готовый текст сообщения, без \"своими словами\".

        ПРАВИЛО СООБЩЕНИЙ (ВАЖНО):
        - Если из тактики логично следует общение (написать другу, преподу, работодателю, агенту и т.п.), ты обязан дать точный текст сообщения.
                - Формат: глагол + канал + готовый текст, например: "Открой WhatsApp и отправь сообщение: '...'."
                - Нельзя писать: \"Напиши другу сообщение\", \"Сформулируй запрос\", \"Напиши что-то честное\".

        ВЕКТОР ПРОГРЕССА:
            - Действие должно бить прямо в цель конкретной задачи пользователя и давать внешний результат за 10-20 минут.
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
        return sanitizeOneAction(
            cleaned,
            intent: inferredIntent,
            highStakes: highStakes,
            choice: choice,
            braindump: braindump,
            insight: insight,
            sourceContext: sourceContext,
            selectedTopic: selectedFocus
        )
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
        selectedTopic: String?,
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
                question: polishQuestionText(question, seedText: sourceText),
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

                return polishFocusResponse(FocusResponse(
                    topics: nil,
                    highlight: fallbackHighlight,
                    insight: fallbackInsight,
                    question: nil,
                    choices: fallbackChoices
                ), intent: intent, sourceText: sourceText, selectedTopic: selectedTopic, userAnswer: userAnswer, highStakes: highStakes)
            }

            return polishFocusResponse(FocusResponse(
                topics: nil,
                highlight: normalized.highlight,
                insight: normalized.insight,
                question: nil,
                choices: normalized.choices
            ), intent: intent, sourceText: sourceText, selectedTopic: selectedTopic, userAnswer: userAnswer, highStakes: highStakes)
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

                return polishFocusResponse(FocusResponse(
                    topics: nil,
                    highlight: fallbackHighlight,
                    insight: fallbackInsight,
                    question: nil,
                    choices: fallbackChoices
                ), intent: intent, sourceText: sourceText, selectedTopic: selectedTopic, userAnswer: userAnswer, highStakes: highStakes)
            }

            return polishFocusResponse(FocusResponse(
                topics: nil,
                highlight: normalized.highlight,
                insight: normalized.insight,
                question: nil,
                choices: normalized.choices
            ), intent: intent, sourceText: sourceText, selectedTopic: selectedTopic, userAnswer: userAnswer, highStakes: highStakes)
        }

        return polishFocusResponse(
            normalized,
            intent: intent,
            sourceText: sourceText,
            selectedTopic: selectedTopic,
            userAnswer: userAnswer,
            highStakes: highStakes
        )
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

    private static func polishFocusResponse(
        _ response: FocusResponse,
        intent: MentorioIntent,
        sourceText: String,
        selectedTopic: String?,
        userAnswer: String?,
        highStakes: Bool
    ) -> FocusResponse {
        if let rawTopics = response.topics, !rawTopics.isEmpty {
            let topics = polishTopics(rawTopics)
            if !topics.isEmpty {
                return FocusResponse(
                    topics: topics,
                    highlight: nil,
                    insight: nil,
                    question: nil,
                    choices: nil
                )
            }
        }

        if let rawQuestion = response.question,
           !rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let question = polishQuestionText(rawQuestion, seedText: sourceText)
            return FocusResponse(
                topics: nil,
                highlight: nil,
                insight: nil,
                question: question,
                choices: nil
            )
        }

        let polishedChoices = polishChoices(
            response.choices ?? [],
            intent: intent,
            sourceText: sourceText,
            selectedTopic: selectedTopic,
            userAnswer: userAnswer,
            highStakes: highStakes
        )

        guard !polishedChoices.isEmpty else {
            return FocusResponse(
                topics: nil,
                highlight: nil,
                insight: nil,
                question: polishQuestionText("Что из этого сейчас самый реальный шаг на 15 минут", seedText: sourceText),
                choices: nil
            )
        }

        let fallbackHighlight = extractFirstMeaningfulSentence(from: sourceText)
        let fallbackInsight = defaultInsight(for: intent, highStakes: highStakes)

        return FocusResponse(
            topics: nil,
            highlight: polishHighlight(response.highlight, fallbackText: fallbackHighlight),
            insight: polishInsight(response.insight, fallbackText: fallbackInsight),
            question: nil,
            choices: polishedChoices
        )
    }

    private static func polishTopics(_ topics: [String]) -> [String] {
        var result: [String] = []

        for topic in topics {
            let cleaned = canonicalizeLabel(topic)
            guard !cleaned.isEmpty else { continue }
            if isDistinctTopic(cleaned, against: result) {
                result.append(cleaned)
            }
            if result.count == 3 {
                break
            }
        }

        return result
    }

    private static func polishQuestionText(_ question: String, seedText: String) -> String {
        var cleaned = question
            .replacingOccurrences(of: #"^[\-•\d\)\.\s]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let lower = cleaned.lowercased()
        let bannedFragments = [
            "давай подумаем",
            "как тебе кажется",
            "в целом",
            "может быть"
        ]

        for fragment in bannedFragments where lower.contains(fragment) {
            cleaned = cleaned.replacingOccurrences(of: fragment, with: "", options: .caseInsensitive)
        }

        cleaned = cleaned
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.count < 12 {
            cleaned = "Что сейчас важнее уточнить: сроки, бюджет или ограничения"
        }

        if cleaned.count > 180 {
            cleaned = String(cleaned.prefix(180)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !cleaned.hasSuffix("?") {
            cleaned = cleaned.replacingOccurrences(of: #"[.!]+$"#, with: "", options: .regularExpression)
            cleaned += "?"
        }

        return normalizeQuestionCTA(cleaned, seedText: seedText)
    }

    private static func polishChoices(
        _ rawChoices: [String],
        intent: MentorioIntent,
        sourceText: String,
        selectedTopic: String?,
        userAnswer: String?,
        highStakes: Bool
    ) -> [String] {
        let selectedFocus = selectedTopic?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveFocusContext: String
        if let selectedFocus, !selectedFocus.isEmpty {
            effectiveFocusContext = selectedFocus
        } else {
            effectiveFocusContext = sourceText
        }

        let fallback = fallbackChoicesForContext(
            intent: intent,
            sourceText: sourceText,
            selectedTopic: selectedTopic,
            userAnswer: userAnswer,
            highStakes: highStakes
        )

        var result: [String] = []

        for raw in rawChoices {
            let cleaned = sanitizeChoiceText(raw)
            guard !cleaned.isEmpty else { continue }
            guard !isWeakChoice(cleaned) else { continue }
            guard !isActionOffDomain(cleaned, choice: effectiveFocusContext) else { continue }
            if let selectedFocus, !selectedFocus.isEmpty,
               !isChoiceAlignedWithSelectedTopic(cleaned, selectedTopic: selectedFocus) {
                continue
            }
            guard isDistinctChoice(cleaned, against: result) else { continue }

            result.append(cleaned)
            if result.count == 2 {
                return result
            }
        }

        for item in fallback where result.count < 2 {
            if let selectedFocus, !selectedFocus.isEmpty,
               !isChoiceAlignedWithSelectedTopic(item, selectedTopic: selectedFocus) {
                continue
            }
            if isDistinctChoice(item, against: result) {
                result.append(item)
            }
        }

        return Array(result.prefix(2))
    }

    private static func sanitizeChoiceText(_ text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: #"^[\-•\d\)\.\s]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        cleaned = normalizeOneActionText(cleaned)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let words = cleaned.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if words.count > 24 {
            cleaned = words.prefix(24).joined(separator: " ")
        }

        guard !cleaned.isEmpty else { return "" }
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }

    private static func isWeakChoice(_ choice: String) -> Bool {
        let lower = choice.lowercased()
        let forbiddenMarkers = [
            "подум", "проанализ", "осознай", "реши в голове", "выбери в голове",
            "отдохни", "мотивац", "подготов", "потом", "когда-нибудь"
        ]

        if forbiddenMarkers.contains(where: { lower.contains($0) }) {
            return true
        }

        if choice.count < 24 {
            return true
        }

        if !startsWithActionVerb(choice) {
            return true
        }

        if !containsArtifactMarker(in: choice) {
            return true
        }

        return false
    }

    private static func isDistinctChoice(_ candidate: String, against existing: [String]) -> Bool {
        let candidateTokens = Set(tokenizeForTopic(candidate))
        guard !candidateTokens.isEmpty else { return false }

        for item in existing {
            let itemTokens = Set(tokenizeForTopic(item))
            guard !itemTokens.isEmpty else { continue }

            let intersection = candidateTokens.intersection(itemTokens).count
            let union = candidateTokens.union(itemTokens).count
            if union > 0 {
                let jaccard = Double(intersection) / Double(union)
                if jaccard >= 0.7 {
                    return false
                }
            }
        }

        return true
    }

    private static func isChoiceAlignedWithSelectedTopic(_ choiceText: String, selectedTopic: String) -> Bool {
        let selectedTokens = anchorTokens(from: selectedTopic)
        if selectedTokens.isEmpty {
            return true
        }

        let choiceTokens = anchorTokens(from: choiceText)
        guard !choiceTokens.isEmpty else { return false }

        return hasTokenOverlap(selectedTokens, choiceTokens)
    }

    private static func fallbackChoicesForContext(
        intent: MentorioIntent,
        sourceText: String,
        selectedTopic: String?,
        userAnswer: String?,
        highStakes: Bool
    ) -> [String] {
        let selectedFocus = selectedTopic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let focusSource = selectedFocus.isEmpty ? extractFirstMeaningfulSentence(from: sourceText) : selectedFocus
        let focusLabel = compactFocusLabel(from: "\(focusSource) \(userAnswer ?? "")")

        if intent == .decisionParalysis || highStakes {
            return [
                "Открой заметки и сравни 2 варианта по критериям ресурс, срок и риск, затем сохрани текущего лидера одной строкой",
                "Открой браузер и сохрани 2 факта для проверки слабого места лидирующего варианта, затем добавь их в заметку"
            ]
        }

        if intent == .preconditionsMissing {
            return [
                "Открой заметки и выпиши 2 доступных варианта получения ресурса сегодня с ценой и сроком",
                "Открой мессенджер и отправь одно сообщение с запросом на доступ или временную альтернативу ресурсу"
            ]
        }

        let context = "\(sourceText) \(userAnswer ?? "")".lowercased()
        if context.contains("перегруз") || context.contains("хаос") || context.contains("завал") || intent == .vagueOverwhelm {
            return [
                "Открой заметки и выпиши 3 конкретных хвоста из текста, затем отметь один для закрытия за 15 минут",
                "Открой календарь и поставь один слот на 20 минут под выбранный хвост, затем сохрани событие"
            ]
        }

        if context.contains("сообщ") || context.contains("позвон") {
            return [
                "Открой мессенджер и отправь одно конкретное сообщение по задаче, затем сохрани отправленный текст в заметку",
                "Открой почту и создай черновик письма с одним запросом по задаче, затем сохрани черновик"
            ]
        }

        return [
            "Открой основной инструмент по теме \"\(focusLabel)\" и за 15 минут создай один черновой результат, затем сохрани его",
            "Открой заметки и зафиксируй один конкретный шаг по теме \"\(focusLabel)\" с критерием готовности, затем выполни шаг и сохрани результат"
        ]
    }

    private static func polishHighlight(_ highlight: String?, fallbackText: String) -> String {
        let source = (highlight?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? highlight!
            : fallbackText

        var cleaned = source
            .replacingOccurrences(of: #"^["'«“”]+|["'»“”]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.count > 140 {
            cleaned = String(cleaned.prefix(140)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned
    }

    private static func polishInsight(_ insight: String?, fallbackText: String) -> String {
        var cleaned = insight?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if cleaned.isEmpty {
            cleaned = fallbackText
        }

        cleaned = cleaned
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let bannedPhrases = [
            "ты сможешь",
            "все получится",
            "не переживай",
            "просто начни"
        ]

        for phrase in bannedPhrases where cleaned.lowercased().contains(phrase) {
            cleaned = cleaned.replacingOccurrences(of: phrase, with: "", options: .caseInsensitive)
        }

        cleaned = cleaned
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.count > 170 {
            cleaned = String(cleaned.prefix(170)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if cleaned.isEmpty {
            return fallbackText
        }

        return cleaned
    }

    private static func defaultInsight(for intent: MentorioIntent, highStakes: Bool) -> String {
        if highStakes || intent == .decisionParalysis {
            return "Сначала фиксируем факты и риски, потом принимаем решение без резких коммитов"
        }

        if intent == .preconditionsMissing {
            return "Точка роста сейчас в шаге, который можно выполнить с текущими ресурсами"
        }

        if intent == .vagueOverwhelm {
            return "Сейчас важнее сократить неопределенность до одного проверяемого шага"
        }

        return "Нужен короткий внешний шаг с видимым результатом, а не внутренний анализ"
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
            "задач", "проект", "работ", "учеб", "клиент", "контекст", "огранич", "критер",
            "инструмент", "ресурс", "срок", "deadline", "requirement", "constraint"
        ]
        return markers.contains(where: { text.contains($0) })
    }

    private static func shouldForceTopicSelection(
        text: String,
        selectedTopic: String?,
        userAnswer: String?,
        clarifyingAttempts: Int
    ) -> Bool {
        let hasSelectedTopic = selectedTopic?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasUserAnswer = userAnswer?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        guard clarifyingAttempts == 0 else { return false }
        guard !hasSelectedTopic && !hasUserAnswer else { return false }

        return independentThemeCount(in: text) >= 3
    }

    private static func independentThemeCount(in text: String) -> Int {
        let ranked = rankedTopicCategories(in: text)
        let highConfidenceCount = ranked.filter { $0.score >= 3 }.count
        return min(4, highConfidenceCount)
    }

    private static func extractForcedTopics(from text: String) -> [String] {
        var topics = extractUserTopicPhrases(from: text)

        let fallback = ["Фокус и приоритеты", "Работа и задачи", "Ресурсы и ограничения"]
        for item in fallback where !topics.contains(item) {
            topics.append(item)
            if topics.count == 3 {
                break
            }
        }

        logTopicSelectionTrace(source: text, selectedTopics: Array(topics.prefix(3)))

        return Array(topics.prefix(3))
    }

    private static func extractUserTopicPhrases(from text: String) -> [String] {
        var result: [String] = []

        for item in rankedTopicCategories(in: text) where item.score >= 2 {
            if !result.contains(item.label) {
                result.append(item.label)
            }
            if result.count == 3 {
                break
            }
        }

        return result
    }

    private static func normalizeTopicCandidate(_ raw: String) -> String {
        var cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^["'«“”]+|["'»“”]+$"#, with: "", options: .regularExpression)

        cleaned = cleaned
            .replacingOccurrences(of: #"^(я|мне|у меня|короче|типа|вообще|просто|ну|блин)\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleaned.count >= 8 else { return "" }

        if let canonical = canonicalTopicLabel(from: cleaned) {
            return canonical
        }

        if let semantic = buildNaturalTopicLabel(from: cleaned) {
            return semantic
        }

        if let ranked = rankedTopicCategories(in: cleaned).first,
           ranked.score >= 2 {
            return ranked.label
        }

        return ""
    }

    private static func rankedTopicCategories(in text: String) -> [(label: String, score: Int)] {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return [] }

        let tokens = Set(
            tokenizeForTopic(lower)
                .map(normalizeTopicToken)
                .filter { token in
                    !token.isEmpty && !isNoisyTopicToken(token)
                }
        )

        let rules: [(label: String, markers: [String])] = [
            ("Фокус и приоритеты", ["фокус", "приоритет", "важн", "распыл", "хаос", "перегруз", "ступор"]),
            ("Работа и задачи", ["работ", "задач", "проект", "результат", "дедлайн", "клиент", "документ"]),
            ("Решение и выбор", ["выбор", "между", "вариант", "решени", "стоит", "сравни"]),
            ("Ресурсы и ограничения", ["ресурс", "бюджет", "деньг", "время", "доступ", "услов", "огранич"]),
            ("Коммуникация и договоренности", ["сообщ", "позвон", "переписк", "запрос", "договор", "обратн"]),
            ("Состояние и энергия", ["устал", "тревог", "выгор", "стресс", "энерг", "мотива", "сон"]),
            ("Навыки и обучение", ["учеб", "курс", "навык", "обуч", "практик", "экзам", "развит"])
        ]

        var scores: [(label: String, score: Int)] = []

        for rule in rules {
            var score = 0
            for marker in rule.markers {
                if lower.contains(marker) {
                    score += 2
                }

                if tokens.contains(where: { token in
                    token.hasPrefix(marker) || marker.hasPrefix(token)
                }) {
                    score += 1
                }
            }

            if score > 0 {
                scores.append((label: rule.label, score: score))
            }
        }

        return scores.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.label < rhs.label
            }
            return lhs.score > rhs.score
        }
    }

    private static func logTopicRoutingTrace(
        source: String,
        selectedTopic: String?,
        userAnswer: String?,
        clarifyingAttempts: Int,
        rankedTopics: [(label: String, score: Int)]
    ) {
#if DEBUG
        let preview = source
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        print("🧭 Topic routing trace: attempts=\(clarifyingAttempts), selected=\(selectedTopic ?? "nil"), answer=\(userAnswer?.isEmpty == false ? "present" : "nil")")
        print("🧭 Topic source preview: \(String(preview.prefix(220)))")
        if rankedTopics.isEmpty {
            print("🧭 Topic ranking: none")
        } else {
            let summary = rankedTopics
                .prefix(6)
                .map { "\($0.label)=\($0.score)" }
                .joined(separator: ", ")
            print("🧭 Topic ranking: \(summary)")
        }
#endif
    }

    private static func logTopicSelectionTrace(source: String, selectedTopics: [String]) {
#if DEBUG
        let preview = source
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        print("🧭 Topic selection trace: \(selectedTopics.joined(separator: " | "))")
        print("🧭 Topic selection source: \(String(preview.prefix(220)))")
#endif
    }

    private static func canonicalTopicLabel(from text: String) -> String? {
        let lower = text.lowercased()

        let decisionMarkers = ["выбор", "между", "или", "сравни", "вариант", "решени", "стоит ли"]
        let resourceMarkers = ["нет", "без", "ресурс", "доступ", "инструмент", "бюджет", "деньг", "нечем"]
        let overwhelmMarkers = ["перегруз", "хаос", "завал", "тревог", "устал", "распыл", "не могу начать"]
        let domain = dominantSemanticDomain(in: lower)

        if decisionMarkers.contains(where: { lower.contains($0) }) {
            if let domain {
                return canonicalizeLabel("Выбор: \(domain)")
            }
            if let keyword = firstTopicKeyword(in: lower, excluding: decisionMarkers + resourceMarkers + overwhelmMarkers) {
                return canonicalizeLabel("Выбор: \(keyword)")
            }
            return "Выбор и решение"
        }

        if resourceMarkers.contains(where: { lower.contains($0) }) {
            if let domain {
                return canonicalizeLabel("Ресурсы: \(domain)")
            }
            if let keyword = firstTopicKeyword(in: lower, excluding: decisionMarkers + resourceMarkers + overwhelmMarkers) {
                return canonicalizeLabel("Ресурсы: \(keyword)")
            }
            return "Ресурс и старт"
        }

        if overwhelmMarkers.contains(where: { lower.contains($0) }) {
            if let domain {
                return canonicalizeLabel("Фокус: \(domain)")
            }
            if let keyword = firstTopicKeyword(in: lower, excluding: decisionMarkers + resourceMarkers + overwhelmMarkers) {
                return canonicalizeLabel("Фокус: \(keyword)")
            }
            return "Фокус и приоритеты"
        }

        return nil
    }

    private static func canonicalizeLabel(_ label: String) -> String {
        let cleaned = label
            .replacingOccurrences(of: #"(?i)^фокус\s+на\s+"#, with: "Фокус: ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^ресурс\s+для\s+"#, with: "Ресурсы: ", options: .regularExpression)
            .replacingOccurrences(of: #"[,.;!?]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let tokens = cleaned
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return "" }

        let maxWords = min(4, tokens.count)
        var clipped = Array(tokens.prefix(maxWords))
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+(и|или)$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #":$"#, with: "", options: .regularExpression)

        clipped = clipped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clipped.isEmpty else { return "" }

        return clipped.prefix(1).uppercased() + clipped.dropFirst()
    }

    private static func firstTopicKeyword(in text: String, excluding markers: [String]) -> String? {
        let excludedTokens = Set(
            markers
                .flatMap { tokenizeForTopic($0) }
                .map(normalizeTopicToken)
        )

        return tokenizeForTopic(text)
            .map(normalizeTopicToken)
            .first { token in
                token.count >= 4 && !excludedTokens.contains(token) && !isNoisyTopicToken(token)
            }
    }

    private static func buildNaturalTopicLabel(from text: String) -> String? {
        let domains = semanticTopicDomains(in: text)
        guard let first = domains.first else { return nil }

        if domains.count >= 2 {
            let second = domains[1]
            if first.score > 0 && second.score > 0 && first.label != second.label {
                return canonicalizeLabel("\(first.label) и \(second.label)")
            }
        }

        if first.score > 0 {
            return canonicalizeLabel(first.label)
        }

        return nil
    }

    private static func dominantSemanticDomain(in text: String) -> String? {
        semanticTopicDomains(in: text).first?.label
    }

    private static func semanticTopicDomains(in text: String) -> [(label: String, score: Int)] {
        let lower = text.lowercased()
        let tokens = tokenizeForTopic(lower).map(normalizeTopicToken)
        guard !tokens.isEmpty else { return [] }

        let domains: [(label: String, markers: [String])] = [
            ("Фокус", ["фокус", "приоритет", "распыл", "хаос", "перегруз", "ступор"]),
            ("Задачи", ["задач", "работ", "проект", "результат", "дедлайн", "документ"]),
            ("Выбор", ["выбор", "вариант", "между", "решени", "сравни", "стоит ли"]),
            ("Ресурсы", ["ресурс", "бюджет", "деньг", "время", "доступ", "огранич", "услов"]),
            ("Коммуникация", ["сообщ", "позвон", "переписк", "запрос", "договор", "обратн"]),
            ("Состояние", ["устал", "тревог", "выгор", "стресс", "энерг", "сон", "мотива"]),
            ("Обучение", ["учеб", "курс", "навык", "обуч", "практик", "экзам", "развит"])
        ]

        var scores: [(label: String, score: Int)] = []
        for domain in domains {
            var score = 0

            for marker in domain.markers {
                if lower.contains(marker) {
                    score += 2
                }

                score += tokens.filter { token in
                    token.hasPrefix(marker) || marker.hasPrefix(token)
                }.count
            }

            if score > 0 {
                scores.append((label: domain.label, score: score))
            }
        }

        return scores.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.label < rhs.label
            }
            return lhs.score > rhs.score
        }
    }

    private static func normalizeTopicToken(_ token: String) -> String {
        let lemmaMap: [String: String] = [
            "дисциплины": "дисциплина",
            "дисциплину": "дисциплина",
            "дисциплиной": "дисциплина",
            "жесткой": "дисциплина",
            "жесткая": "дисциплина",
            "прокрастинирую": "прокрастинация",
            "прокрастинации": "прокрастинация",
            "состоянию": "состояние",
            "состояния": "состояние",
            "состоянии": "состояние",
            "работе": "работа",
            "работы": "работа",
            "работу": "работа",
            "работой": "работа",
            "работаю": "работа",
            "учусь": "учеба",
            "обучении": "учеба",
            "обучение": "учеба",
            "дней": "сроки",
            "дня": "сроки",
            "день": "сроки",
            "неделю": "сроки",
            "недели": "сроки",
            "недель": "сроки",
            "месяца": "сроки",
            "дедлайна": "дедлайн",
            "дедлайну": "дедлайн",
            "денег": "бюджет",
            "деньги": "бюджет",
            "бюджета": "бюджет",
            "бюджету": "бюджет",
            "ресурса": "ресурсы",
            "ресурсов": "ресурсы",
            "сил": "состояние",
            "силы": "состояние",
            "энергии": "состояние",
            "варианта": "выбор",
            "вариантов": "выбор",
            "решения": "выбор",
            "решению": "выбор"
        ]

        let cleaned = token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if cleaned.range(of: #"^\d+$"#, options: .regularExpression) != nil {
            return ""
        }

        return lemmaMap[cleaned] ?? cleaned
    }

    private static func isNoisyTopicToken(_ token: String) -> Bool {
        let noise: Set<String> = [
            "через", "сейчас", "потом", "снова", "очень", "почти", "просто", "нужно", "надо",
            "могу", "можно", "над", "под", "третий", "третью", "второй", "первый", "пару", "несколько",
            "этого", "этой", "этом", "эти", "такой", "такое",
            "три", "года", "год", "лет", "месяц", "месяца", "неделя", "недели", "день", "дней",
            "уже", "вроде", "даже", "просто", "тупо"
        ]

        if token.count < 3 {
            return true
        }

        if noise.contains(token) {
            return true
        }

        if token.range(of: #"^\d+$"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    private static func isDistinctTopic(_ candidate: String, against existing: [String]) -> Bool {
        let candidateTokens = Set(tokenizeForTopic(candidate))
        guard !candidateTokens.isEmpty else { return false }

        for item in existing {
            let itemTokens = Set(tokenizeForTopic(item))
            guard !itemTokens.isEmpty else { continue }

            let intersection = candidateTokens.intersection(itemTokens).count
            let union = candidateTokens.union(itemTokens).count
            if union > 0 {
                let jaccard = Double(intersection) / Double(union)
                if jaccard >= 0.55 {
                    return false
                }
            }
        }

        return true
    }

    private static func tokenizeForTopic(_ text: String) -> [String] {
        let stopWords: Set<String> = [
            "и", "а", "но", "или", "что", "как", "это", "этот", "эта", "эти", "тут", "там", "уже", "еще",
            "очень", "просто", "вообще", "когда", "потому", "если", "чтобы", "для", "про", "по", "в", "на", "с", "из", "к", "до",
            "я", "мне", "меня", "мы", "ты", "он", "она", "они", "мой", "моя", "мои", "свой", "своя", "свои",
            "надо", "нужно", "хочу", "могу", "мочь", "буду", "есть", "нет", "бы", "же", "ли", "ну", "да", "не"
        ]

        return text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                token.count >= 3 && !stopWords.contains(token)
            }
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
            "вариант", "решение", "как поступить", "какой путь"
        ]

        if strongMarkers.contains(where: { text.contains($0) }) {
            return true
        }

        let hasEither = text.contains(" или ") || text.hasPrefix("или ") || text.hasSuffix(" или")
        let decisionContextMarkers = ["вариант", "между", "выбор", "что лучше", "сравни"]
        if hasEither && decisionContextMarkers.contains(where: { text.contains($0) }) {
            return true
        }

        let weakMarkers = ["вариант", "решени", "сравни", "между", "что лучше", "стоит ли"]
        let weakHits = weakMarkers.filter { text.contains($0) }.count
        return weakHits >= 2
    }

    private static func isPreconditionsMissingInput(_ text: String) -> Bool {
        let markers = [
            "не могу начать без", "без этого не могу", "нет денег", "нет бюджета", "нет ресурса",
            "сначала купить", "пока не куплю", "нет доступа", "нечем", "нет инструмента",
            "нет условий", "нет времени", "нет возможности"
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

    private static func sanitizeOneAction(
        _ action: String,
        intent: MentorioIntent,
        highStakes: Bool,
        choice: String,
        braindump: String,
        insight: String,
        sourceContext: String,
        selectedTopic: String?
    ) -> String {
        let fallbackGeneric = "Открой заметки и за 10 минут запиши один следующий шаг по выбранной тактике и сохрани запись"
        let fallbackHighStakes = "Открой заметки и за 10 минут сравни оба варианта по 3 критериям (цена, ключевая задача, риски) и зафиксируй текущего лидера одной строкой"
        let normalized = normalizeOneActionText(action)
        let contextualFallback = fallbackActionForChoice(
            choice: choice,
            intent: intent,
            highStakes: highStakes,
            fallbackGeneric: fallbackGeneric,
            fallbackHighStakes: fallbackHighStakes,
            braindump: braindump,
            insight: insight,
            sourceContext: sourceContext,
            selectedTopic: selectedTopic
        )

        guard !normalized.isEmpty else {
            print("⚠️ OneAction fallback: empty model output")
            return contextualFallback
        }

        let lower = normalized.lowercased()
        let forbiddenCommitMarkers = [
            "купи", "купить", "оплати", "оплатить", "закажи", "заказать",
            "оформи кредит", "подпиши", "подписать", "уволь", "переез", "финальн"
        ]

        if (intent == .decisionParalysis || highStakes) && forbiddenCommitMarkers.contains(where: { lower.contains($0) }) {
            print("⚠️ OneAction fallback: forbidden commit marker detected")
            return fallbackHighStakes
        }

        let hasValidVerb = startsWithActionVerb(normalized)
        let hasArtifact = containsArtifactMarker(in: normalized)
        guard hasValidVerb && hasArtifact else {
            print("⚠️ OneAction fallback: validation failed (verb=\(hasValidVerb), artifact=\(hasArtifact))")
            return contextualFallback
        }

        if isActionOffDomain(normalized, choice: choice) {
            print("⚠️ OneAction fallback: off-domain action rejected")
            print("   choice=\(choice)")
            print("   action=\(normalized)")
            return contextualFallback
        }

        if !hasChoiceAnchor(action: normalized, choice: choice) {
            print("⚠️ OneAction fallback: weak lexical anchor to selected choice")
            print("   choice=\(choice)")
            print("   action=\(normalized)")
            return contextualFallback
        }

        if let selectedTopic,
           !selectedTopic.isEmpty,
           !isChoiceAlignedWithSelectedTopic(normalized, selectedTopic: selectedTopic) {
            print("⚠️ OneAction fallback: selected-topic mismatch")
            print("   selectedTopic=\(selectedTopic)")
            print("   action=\(normalized)")
            return contextualFallback
        }

        let requiredFocusText = "\(choice) \(sourceContext)"
        let optionalFocusText = "\(braindump) \(insight)"
        if !isActionAlignedWithFocus(
            action: normalized,
            requiredFocusText: requiredFocusText,
            optionalFocusText: optionalFocusText
        ) {
            print("⚠️ OneAction fallback: action not aligned with focus domain")
            print("   requiredFocus=\(requiredFocusText)")
            print("   optionalFocus=\(optionalFocusText)")
            print("   action=\(normalized)")
            return contextualFallback
        }

        if isRedundantSocialResearch(action: normalized, braindump: braindump, choice: choice, insight: insight, sourceContext: sourceContext) {
            print("⚠️ OneAction fallback: redundant social research rejected")
            print("   choice=\(choice)")
            print("   action=\(normalized)")
            return contextualFallback
        }

        return normalized
    }

    private static func normalizeOneActionText(_ action: String) -> String {
        var text = action
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip only wrapper quotes around the whole command, but keep quotes used inside message templates.
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

    private static func startsWithActionVerb(_ action: String) -> Bool {
        let lower = action.lowercased()
        let verbs = [
            "открой", "нажми", "запиши", "вставь", "запусти", "отправь", "позвони", "найди", "создай",
            "сохрани", "заполни", "сравни", "зайди", "напиши", "составь", "загрузи", "добавь", "собери"
        ]

        return verbs.contains(where: { lower == $0 || lower.hasPrefix("\($0) ") })
    }

    private static func containsArtifactMarker(in action: String) -> Bool {
        let lower = action.lowercased()
        let markers = [
            "заметк", "файл", "сообщен", "звон", "заявк", "сохран", "таблиц", "документ", "проект",
            "черновик", "письмо", "чат", "форма", "скриншот"
        ]

        return markers.contains(where: { lower.contains($0) })
    }

    private static func isActionOffDomain(_ action: String, choice: String) -> Bool {
        let choiceTokens = anchorTokens(from: choice)
        let actionTokens = anchorTokens(from: action)

        guard !choiceTokens.isEmpty && !actionTokens.isEmpty else {
            return false
        }

        if hasTokenOverlap(choiceTokens, actionTokens) {
            return false
        }

        if hasChoiceAnchor(action: action, choice: choice) {
            return false
        }

        let actionLower = action.lowercased()
        let choiceLower = choice.lowercased()
        let explicitFinancial = ["кредит", "ипотек", "долг", "процент", "взнос"]
        if explicitFinancial.contains(where: { actionLower.contains($0) }) &&
            !explicitFinancial.contains(where: { choiceLower.contains($0) }) {
            return true
        }

        return true
    }

    private static func isActionAlignedWithFocus(
        action: String,
        requiredFocusText: String,
        optionalFocusText: String
    ) -> Bool {
        let actionTokens = anchorTokens(from: action)
        guard !actionTokens.isEmpty else { return false }

        let requiredFocusTokens = anchorTokens(from: requiredFocusText)
        if !requiredFocusTokens.isEmpty {
            return hasTokenOverlap(requiredFocusTokens, actionTokens)
        }

        let optionalFocusTokens = anchorTokens(from: optionalFocusText)
        if !optionalFocusTokens.isEmpty {
            return hasTokenOverlap(optionalFocusTokens, actionTokens)
        }

        return true
    }

    private static func anchorTokens(from text: String) -> Set<String> {
        Set(
            tokenizeForTopic(text)
                .map(normalizeTopicToken)
                .filter { token in
                    token.count >= 4 && !isNoisyTopicToken(token)
                }
        )
    }

    private static func hasTokenOverlap(_ lhs: Set<String>, _ rhs: Set<String>) -> Bool {
        if !lhs.isDisjoint(with: rhs) {
            return true
        }

        for left in lhs {
            if rhs.contains(where: { right in
                right.hasPrefix(left) || left.hasPrefix(right)
            }) {
                return true
            }
        }

        return false
    }

    private static func compactFocusLabel(from text: String) -> String {
        let tokens = Array(anchorTokens(from: text).prefix(6))
        if tokens.isEmpty {
            return "текущей задаче"
        }
        return tokens.joined(separator: " ")
    }

    static func validateContextAnchoring(
        braindump: String,
        selectedTopic: String?,
        userAnswer: String?,
        candidates: [String]
    ) -> [String] {
        let source = [braindump, selectedTopic ?? "", userAnswer ?? ""]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let allowedTokens = anchorTokens(from: source)
        guard !allowedTokens.isEmpty else {
            return []
        }

        var violations: [String] = []
        for (index, candidate) in candidates.enumerated() {
            let candidateTokens = anchorTokens(from: candidate)
            if candidateTokens.isEmpty {
                violations.append("candidate_\(index): empty_anchor_tokens")
                continue
            }

            let meaningfulCandidateTokens = candidateTokens.filter { !isOperationalToken($0) }
            let overlapExists = hasTokenOverlap(Set(meaningfulCandidateTokens), allowedTokens) ||
                hasTokenOverlap(candidateTokens, allowedTokens)

            if !overlapExists {
                violations.append("candidate_\(index): no_context_overlap")
                continue
            }

            let unexpected = meaningfulCandidateTokens.filter { token in
                !allowedTokens.contains(where: { allowed in
                    allowed == token || allowed.hasPrefix(token) || token.hasPrefix(allowed)
                })
            }

            if meaningfulCandidateTokens.count >= 3 {
                let ratio = Double(unexpected.count) / Double(meaningfulCandidateTokens.count)
                if ratio > 0.55 && unexpected.count >= 2 {
                    violations.append("candidate_\(index): high_unexpected_ratio")
                }
            }
        }

        return violations
    }

    #if DEBUG
    static func runContextAnchoringRegressionSuite() -> [String] {
        struct RegressionCase {
            let title: String
            let braindump: String
            let selectedTopic: String?
            let userAnswer: String?
        }

        let cases: [RegressionCase] = [
            RegressionCase(
                title: "career_switch",
                braindump: "Полгода откладываю смену работы. Есть резюме, но каждый вечер закрываю ноут и ничего не отправляю.",
                selectedTopic: "Смена работы и отклики",
                userAnswer: nil
            ),
            RegressionCase(
                title: "study_deadline",
                braindump: "До экзамена неделя, а я застрял и не могу начать подготовку по билетам.",
                selectedTopic: "Подготовка к экзамену",
                userAnswer: nil
            ),
            RegressionCase(
                title: "communication_conflict",
                braindump: "Нужно обсудить конфликт с партнером, но избегаю разговора и тяну время.",
                selectedTopic: "Сложный разговор",
                userAnswer: nil
            ),
            RegressionCase(
                title: "resource_blocker",
                braindump: "Не запускаю задачу, потому что кажется, что сначала нужны дополнительные ресурсы.",
                selectedTopic: "Старт с текущими ресурсами",
                userAnswer: "Ресурс полезен, но можно сделать первый шаг без него"
            )
        ]

        var report: [String] = []

        for item in cases {
            let intent = detectIntent(text: item.braindump, selectedTopic: item.selectedTopic, userAnswer: item.userAnswer)
            let highStakes = isHighStakesDecision(text: item.braindump, intent: intent)

            let choices = fallbackChoicesForContext(
                intent: intent,
                sourceText: item.braindump,
                selectedTopic: item.selectedTopic,
                userAnswer: item.userAnswer,
                highStakes: highStakes
            )

            let firstChoice = choices.first ?? ""
            let fallbackAction = fallbackActionForChoice(
                choice: firstChoice,
                intent: intent,
                highStakes: highStakes,
                fallbackGeneric: "Открой заметки и за 10 минут запиши один следующий шаг по выбранной тактике и сохрани запись",
                fallbackHighStakes: "Открой заметки и сравни 2 варианта по 3 критериям, затем зафиксируй текущего лидера",
                braindump: item.braindump,
                insight: "",
                sourceContext: firstChoice,
                selectedTopic: item.selectedTopic
            )

            let choicesViolations = validateContextAnchoring(
                braindump: item.braindump,
                selectedTopic: item.selectedTopic,
                userAnswer: item.userAnswer,
                candidates: choices
            )

            let actionViolations = validateContextAnchoring(
                braindump: item.braindump,
                selectedTopic: item.selectedTopic,
                userAnswer: item.userAnswer,
                candidates: [fallbackAction]
            )

            if choicesViolations.isEmpty && actionViolations.isEmpty {
                report.append("PASS: \(item.title)")
            } else {
                let details = (choicesViolations + actionViolations).joined(separator: ", ")
                report.append("FAIL: \(item.title) -> \(details)")
            }
        }

        return report
    }
    #endif

    private static func isOperationalToken(_ token: String) -> Bool {
        let operational: Set<String> = [
            "открой", "создай", "сохрани", "запиши", "сравни", "отправ", "позвон",
            "заметк", "файл", "документ", "черновик", "сообщ", "шаг", "критер", "результ"
        ]

        return operational.contains(where: { marker in
            token.hasPrefix(marker) || marker.hasPrefix(token)
        })
    }

    private static func hasChoiceAnchor(action: String, choice: String) -> Bool {
        let choiceTokens = Set(tokenizeForTopic(choice).filter { $0.count >= 4 })
        guard !choiceTokens.isEmpty else { return true }

        let actionTokens = Set(
            tokenizeForTopic(action)
                .filter { $0.count >= 4 }
        )
        guard !actionTokens.isEmpty else { return false }

        if !choiceTokens.isDisjoint(with: actionTokens) {
            return true
        }

        for choiceToken in choiceTokens {
            if actionTokens.contains(where: { $0.hasPrefix(choiceToken) || choiceToken.hasPrefix($0) }) {
                return true
            }
        }

        return false
    }

    private static func fallbackActionForChoice(
        choice: String,
        intent: MentorioIntent,
        highStakes: Bool,
        fallbackGeneric: String,
        fallbackHighStakes: String,
        braindump: String,
        insight: String,
        sourceContext: String,
        selectedTopic: String?
    ) -> String {
        let lower = choice.lowercased()
        let selectedFocus = selectedTopic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let choiceContext = "\(selectedFocus) \(choice) \(sourceContext)"
        let globalContext = "\(braindump) \(insight)".lowercased()
        let mergedContext = "\(choiceContext.lowercased()) \(globalContext)"
        let focusLabel = compactFocusLabel(from: "\(choiceContext) \(braindump)")

        if intent == .decisionParalysis || highStakes {
            if ["деньг", "бюджет", "работ", "срок", "риск", "ресурс", "время"].contains(where: { mergedContext.contains($0) }) {
                return "Открой заметки и сравни 2 варианта по 3 критериям: ресурс, срок и риск, затем зафиксируй текущего лидера одной строкой"
            }
            return fallbackHighStakes
        }

        if ["напис", "сообщ", "позвон", "связ", "спрос"].contains(where: { lower.contains($0) }) {
            return "Открой мессенджер и отправь одно сообщение по выбранной тактике с конкретным запросом и сохрани отправку"
        }

        if ["перегруз", "фокус", "завал", "хаос", "распыл", "ступор", "устал", "тревог"].contains(where: { lower.contains($0) }) {
            return "Открой заметки и выпиши 3 открытых хвоста по выбранной теме, затем отметь один, который можно закрыть за 15 минут"
        }

        if ["проект", "задач", "работ", "документ", "файл", "отчет", "материал"].contains(where: { lower.contains($0) }) {
            return "Открой рабочий инструмент по выбранной тактике и сохрани один минимальный результат в файл"
        }

        if ["учеб", "курс", "экзам", "язык", "урок", "study"].contains(where: { lower.contains($0) }) {
            return "Открой учебный материал по выбранной тактике и сохрани конспект из 5 пунктов в заметку"
        }

        if ["деньг", "бюджет", "долг", "кредит", "расход", "доход", "цена"].contains(where: { lower.contains($0) }) {
            return "Открой заметки и за 10 минут выпиши 3 факта по расходам и срокам и сохрани запись"
        }

        let universal = "Открой основной инструмент по теме \"\(focusLabel)\" и за 15 минут создай один наблюдаемый результат, затем сохрани его в файл или заметку"
        return universal.isEmpty ? fallbackGeneric : universal
    }

    private static func isRedundantSocialResearch(action: String, braindump: String, choice: String, insight: String, sourceContext: String) -> Bool {
        let actionLower = action.lowercased()
        let contextLower = "\(braindump) \(choice) \(insight) \(sourceContext)".lowercased()

        let socialMarkers = ["знаком", "друз", "спрос", "свяж", "узнай", "поговор", "мнение", "опыт жизни", "как там", "что думают"]
        guard socialMarkers.contains(where: { actionLower.contains($0) }) else {
            return false
        }

        let firstHandMarkers = ["уже", "сейчас", "я жив", "я работ", "я уч", "у меня", "мой опыт", "пробовал"]
        let hasFirstHandContext = firstHandMarkers.contains(where: { contextLower.contains($0) })

        let criteriaMarkers = ["критер", "срок", "риск", "ресурс", "стоим", "цена", "бюджет", "огранич", "плюс", "минус"]
        let hasConcreteCriteria = criteriaMarkers.contains(where: { actionLower.contains($0) })

        return hasFirstHandContext && !hasConcreteCriteria
    }

    private static func extractOneActionSourceContext(
        from braindump: String,
        highlight: String,
        insight: String,
        choice: String,
        selectedTopic: String?
    ) -> String {
        var frequency: [String: Int] = [:]

        let weightedSources: [(text: String, weight: Int)] = [
            (selectedTopic?.lowercased() ?? "", 6),
            (choice.lowercased(), 4),
            (highlight.lowercased(), 2),
            (insight.lowercased(), 1),
            (braindump.lowercased(), 1)
        ]

        for source in weightedSources {
            for token in tokenizeForTopic(source.text) where token.count >= 4 {
                frequency[token, default: 0] += source.weight
            }
        }

        let topTokens = frequency
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(6)
            .map { $0.key }

        let braindumpAnchor = extractFirstMeaningfulSentence(from: braindump)
        let compactAnchor = String(braindumpAnchor.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)

        if !topTokens.isEmpty {
            return "фокус: \(topTokens.joined(separator: ", ")); якорь: \(compactAnchor)"
        }

        return compactAnchor
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

        // Generic signal: if text has too few meaningful tokens and no clear structure, treat as vague.
        let meaningfulTokens = tokenizeForTopic(trimmed)
        let hasStructure = trimmed.contains("\n") || trimmed.contains(":") || trimmed.contains(",")

        return meaningfulTokens.count < 3 && !hasStructure
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
#endif
