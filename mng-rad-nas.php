<?php 
/*
 *********************************************************************************************************
 * daloRADIUS - RADIUS Web Platform
 * Copyright (C) 2007 - Liran Tal <liran@lirantal.com> All Rights Reserved.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 *
 *********************************************************************************************************
 *
 * Authors:    Liran Tal <liran@lirantal.com>
 *             Filippo Lauria <filippo.lauria@iit.cnr.it>
 *
 *********************************************************************************************************
 */

    include ("library/checklogin.php");
    $operator = $_SESSION['operator_user'];

    include_once('../common/includes/config_read.php');
    $log = "visited page: ";

    // RADIUS 재시작 로직
    if (isset($_POST['restart_radius'])) {
        $command = "sudo /usr/bin/systemctl restart radiusd.service 2>&1";
        $return_code = 1; // 실패로 초기화
        $output = array();

        exec($command, $output, $return_code);

        if ($return_code === 0) {
            $message = "RADIUS 데몬이 성공적으로 재시작되었습니다. 🥳";
        } else {
            $error_message = implode("\n", $output);
            $message = "RADIUS 데몬 재시작 실패. 😥<br>오류 코드: " . $return_code . "<br>오류 메시지: <pre>" . $error_message . "</pre>";
            
            // "sudo: a password is required" 오류 메시지가 포함된 경우
            if (strpos($error_message, 'sudo: a password is required') !== false) {
                $message .= "<br><br><b>💡 문제 해결 방법:</b><br>";
                $message .= "이 문제는 웹 서버가 sudo 명령을 실행할 권한이 없기 때문입니다. 아래 명령어로 sudoers 파일을 수정하여 비밀번호 없이 실행할 수 있도록 허용해야 합니다.";
                $message .= "<br><br><code><b>1. sudo visudo 를 실행합니다.</b></code><br>";
                $message .= "<code><b>2. 파일 맨 아래에 다음 줄을 추가한후 브라우저를 refresh 하세요.:</b></code><br>";
                $message .= "<code><b>apache ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart radiusd.service</b></code><br>";
            }
        }
    }

    include_once("lang/main.php");
    
    include("../common/includes/layout.php");

    // print HTML prologue
    $title = t('Intro','mngradnas.php');
    $help = t('helpPage','mngradnas');
    
    print_html_prologue($title, $langCode);

    print_title_and_help($title, $help);
    
    // 1. NAS 추가 안내 문구
    echo "<p class='mb-3'><b>※ NAS 추가후 반드시 RADIUS Restart 버튼을 클릭하여 Radius 서비스를 재시작하세요.</b></p>";

    // 2. 재시작 결과 알림 메시지 (daloRADIUS 2.3 Bootstrap alert 스타일 적용)
    if (isset($message)) {
        $alert_class = ($return_code === 0) ? "alert-success" : "alert-danger";
        echo "<div class='alert {$alert_class} my-3' role='alert'>";
        echo $message;
        echo "</div>";
    }

    include('include/config/logging.php');

    print_footer_and_html_epilogue();

?>
