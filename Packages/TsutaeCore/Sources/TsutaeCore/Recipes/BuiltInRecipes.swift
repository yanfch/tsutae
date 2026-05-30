import Foundation

/// 内置配方模板
/// 对应文档: gui-tui/docs/08-recipes.md
///
/// 用户可以通过设置页 "Add from template" 导入这些配方
public enum BuiltInRecipes {
    
    /// 所有内置配方模板
    public static let all: [Recipe] = [
        notionDaily,
        obsidianDaily,
        linearIssue,
        slackMe,
        orchestratorDispatch,
    ]
    
    // MARK: - Notion (写入 daily database)
    
    /// Notion daily 配方
    /// 需要 secrets: `notion_token`, `notion_daily_db_id`
    public static let notionDaily = Recipe(
        name: "notion_daily",
        description: "写入 Notion daily database",
        action: "post_http",
        url: "https://api.notion.com/v1/pages",
        method: "POST",
        headers: [
            "Authorization": "Bearer {{secrets.notion_token}}",
            "Notion-Version": "2022-06-28",
            "Content-Type": "application/json",
        ],
        bodyFormat: "json",
        body: """
            {
              "parent": {
                "database_id": "{{secrets.notion_daily_db_id}}"
              },
              "properties": {
                "Name": {
                  "title": [{ "text": { "content": "{{transcription | first_line | truncate(80)}}" }}]
                },
                "Date": {
                  "date": { "start": "{{date}}" }
                },
                "Source": {
                  "select": { "name": "VoiceBar" }
                }
              },
              "children": [
                {
                  "object": "block",
                  "type": "paragraph",
                  "paragraph": {
                    "rich_text": [{ "type": "text", "text": { "content": "{{transcription}}" }}]
                  }
                }
              ]
            }
            """,
        timeoutMs: 5000,
        retry: 1,
        onSuccess: RecipeCallback(tts: "已写入 Notion"),
        onFailure: RecipeCallback(tts: "Notion 写入失败", logToClipboard: true)
    )
    
    // MARK: - Obsidian (追加到 daily note)
    
    /// Obsidian daily note 配方
    /// 需要: Obsidian Local REST API plugin
    /// 需要 secrets: `obsidian_token`
    public static let obsidianDaily = Recipe(
        name: "obsidian_daily",
        description: "追加到 Obsidian daily note",
        action: "post_http",
        url: "http://127.0.0.1:27124/vault/Daily/{{date}}.md",
        method: "POST",
        headers: [
            "Authorization": "Bearer {{secrets.obsidian_token}}",
            "Content-Type": "text/markdown",
        ],
        bodyFormat: "text",
        body: """
            
            - [{{time}}] {{transcription}}
            """,
        timeoutMs: 3000,
        retry: 0,
        onSuccess: RecipeCallback(tts: "已写入 Obsidian"),
        onFailure: RecipeCallback(tts: "Obsidian 写入失败", logToClipboard: true)
    )
    
    // MARK: - Linear (创建新 issue)
    
    /// Linear issue 配方
    /// 需要 secrets: `linear_token`, `linear_team_id`
    public static let linearIssue = Recipe(
        name: "linear_issue",
        description: "创建 Linear issue",
        action: "post_http",
        url: "https://api.linear.app/graphql",
        method: "POST",
        headers: [
            "Authorization": "{{secrets.linear_token}}",
            "Content-Type": "application/json",
        ],
        bodyFormat: "json",
        body: """
            {
              "query": "mutation IssueCreate($input: IssueCreateInput!) { issueCreate(input: $input) { success issue { identifier url } } }",
              "variables": {
                "input": {
                  "teamId": "{{secrets.linear_team_id}}",
                  "title": "{{transcription | first_line | truncate(80)}}",
                  "description": "{{transcription}}\\n\\n---\\nCreated via VoiceBar at {{timestamp_iso}}"
                }
              }
            }
            """,
        timeoutMs: 5000,
        retry: 1,
        onSuccess: RecipeCallback(tts: "已创建 Linear issue"),
        onFailure: RecipeCallback(tts: "Linear 创建失败", logToClipboard: true)
    )
    
    // MARK: - Slack (发送到 #me)
    
    /// Slack webhook 配方
    /// 需要 secrets: `slack_webhook_url`
    public static let slackMe = Recipe(
        name: "slack_me",
        description: "发送到 Slack #me 频道",
        action: "post_http",
        url: "{{secrets.slack_webhook_url}}",
        method: "POST",
        headers: [
            "Content-Type": "application/json",
        ],
        bodyFormat: "json",
        body: """
            {
              "text": "{{transcription}}",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "{{transcription | markdown_escape}}"
                  }
                },
                {
                  "type": "context",
                  "elements": [
                    {
                      "type": "mrkdwn",
                      "text": "🕐 {{time}} via VoiceBar"
                    }
                  ]
                }
              ]
            }
            """,
        timeoutMs: 5000,
        retry: 1,
        onSuccess: RecipeCallback(tts: "已发送到 Slack"),
        onFailure: RecipeCallback(tts: "Slack 发送失败", logToClipboard: true)
    )
    
    // MARK: - Orchestrator (派任务)
    
    /// Orchestrator 任务派发配方
    public static let orchestratorDispatch = Recipe(
        name: "orchestrator_dispatch",
        description: "派任务给 AgentOrchestrator",
        action: "post_http",
        url: "http://127.0.0.1:7777/v1/tasks",
        method: "POST",
        headers: [
            "Content-Type": "application/json",
        ],
        bodyFormat: "json",
        body: """
            {
              "input": "{{transcription}}",
              "source": "voicebar",
              "timestamp": "{{timestamp_iso}}",
              "context": {
                "focused_app": "{{focused_app}}",
                "cwd": "{{cwd}}"
              }
            }
            """,
        timeoutMs: 10000,
        retry: 0,
        onSuccess: RecipeCallback(tts: "任务已派发"),
        onFailure: RecipeCallback(tts: "派发失败", logToClipboard: true)
    )
    
    // MARK: - 安装内置配方
    
    /// 将内置配方安装到 `~/.tsutae/recipes/`（如果不存在）
    public static func installDefaults() throws {
        for recipe in all {
            if !RecipeLoader.exists(name: recipe.name) {
                try RecipeLoader.save(recipe)
            }
        }
    }
}
