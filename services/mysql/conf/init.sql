-- MySQL 初始化脚本
-- 仅在数据目录为空时执行（即首次启动）
-- 用于演示 K8s 中 "PVC 为空时自动跑初始化" 的行为

CREATE DATABASE IF NOT EXISTS cfa CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE cfa;

CREATE TABLE IF NOT EXISTS articles (
    id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    title      VARCHAR(255)    NOT NULL,
    content    TEXT            NOT NULL,
    created_at TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 测试数据
INSERT INTO articles (title, content) VALUES
    ('K8s 学习笔记 1', '这是第一篇笔记，记录 Namespace 与 Pod 的基本用法。'),
    ('K8s 学习笔记 2', '这是第二篇笔记，记录 Deployment 与 Service。');