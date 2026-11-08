提交格式：english-prefix: 中文描述
示例：fix: 修正首页文案
允许前缀：feat, fix, docs, refactor, test, chore, build, ci, security

构建与验证：./build.sh、swift test --configuration release（或 ./test.sh 一次完成）。测试用例与断言统一使用 Swift Testing，测试代码不得编入发布 App。
默认图标源为 Assets/AppIcon-v5-vector.svg。应用标识统一为 io.github.chenmobuys.Neylu，不保留旧品牌兼容逻辑。
不要提交密钥、证书、个人监控数据、生成的应用或构建缓存。
