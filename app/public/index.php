<?php
/**
 * CFA 应用入口
 *
 * 用于演示 K8s 中 PHP 应用如何连接 MySQL / Redis / Elasticsearch。
 * 所有连接参数（含密码）一律来自环境变量，代码不保留任何明文兜底：
 *   - K8s     ：由 Secret cfa-secret 注入（见 k8s/php/deployment.yaml）
 *   - Compose ：由 .env 注入（见 .env.example）
 */

declare(strict_types=1);

// 简易路由
$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';

header('Content-Type: text/plain; charset=utf-8');

switch ($path) {
    case '/':
        echo home();
        break;
    case '/health':
        echo health();
        break;
    case '/mysql':
        echo mysqlDemo();
        break;
    case '/redis':
        echo redisDemo();
        break;
    case '/es':
        echo esDemo();
        break;
    default:
        http_response_code(404);
        echo "404 Not Found: {$path}\n";
}

function home(): string
{
    $hostname = gethostname();
    $lines = [
        '=== CFA PHP App ===',
        "Pod hostname: {$hostname}",
        "Time: " . date('Y-m-d H:i:s'),
        '',
        '可用路由:',
        '  GET /         本页',
        '  GET /health   健康检查',
        '  GET /mysql    测试 MySQL 连接',
        '  GET /redis    测试 Redis 连接',
        '  GET /es       测试 Elasticsearch 连接',
    ];
    return implode("\n", $lines) . "\n";
}

function health(): string
{
    return "OK\n";
}

function mysqlDemo(): string
{
    $host = getenv('MYSQL_HOST') ?: 'mysql';
    $port = getenv('MYSQL_PORT') ?: '3306';
    $db   = getenv('MYSQL_DB')   ?: 'cfa';
    $user = getenv('MYSQL_USER') ?: 'cfa';
    $pass = getenv('MYSQL_PASSWORD');

    if ($pass === false || $pass === '') {
        return "MySQL FAIL: 未配置 MYSQL_PASSWORD（K8s 由 cfa-secret 注入，Compose 由 .env 注入）\n";
    }

    try {
        $dsn = "mysql:host={$host};port={$port};dbname={$db};charset=utf8mb4";
        $pdo = new PDO($dsn, $user, $pass, [PDO::ATTR_TIMEOUT => 3]);
        $ver = $pdo->query('SELECT VERSION()')->fetchColumn();
        return "MySQL OK: {$ver} @ {$host}\n";
    } catch (Throwable $e) {
        return "MySQL FAIL: " . $e->getMessage() . "\n";
    }
}

function redisDemo(): string
{
    $host = getenv('REDIS_HOST') ?: 'redis';
    $port = getenv('REDIS_PORT') ?: '6379';

    try {
        $sock = @fsockopen($host, (int)$port, $errno, $errstr, 3);
        if (!$sock) {
            return "Redis FAIL: {$errstr} ({$errno})\n";
        }
        fwrite($sock, "*1\r\n\$4\r\nPING\r\n");
        $resp = fread($sock, 64);
        fclose($sock);
        return "Redis OK: " . trim($resp) . "\n";
    } catch (Throwable $e) {
        return "Redis FAIL: " . $e->getMessage() . "\n";
    }
}

function esDemo(): string
{
    $host = getenv('ES_HOST') ?: 'elasticsearch';
    $port = getenv('ES_PORT') ?: '9200';
    $user = getenv('ES_USER') ?: 'elastic';
    $pass = getenv('ELASTIC_PASSWORD');

    if ($pass === false || $pass === '') {
        return "ES FAIL: 未配置 ELASTIC_PASSWORD（ES 已启用 xpack.security，必须认证）\n";
    }

    $url  = "http://{$host}:{$port}/_cluster/health";

    // ES 8.x 默认开启安全认证，必须携带 Basic Auth
    $auth = 'Authorization: Basic ' . base64_encode("{$user}:{$pass}");
    $ctx  = stream_context_create(['http' => ['timeout' => 3, 'header' => $auth]]);
    $resp = @file_get_contents($url, false, $ctx);
    if ($resp === false) {
        return "ES FAIL: cannot reach {$url}（检查认证或网络）\n";
    }
    $data = json_decode($resp, true);
    return sprintf("ES OK: status=%s, nodes=%d\n", $data['status'] ?? '?', $data['number_of_nodes'] ?? 0);
}