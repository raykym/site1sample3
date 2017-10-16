use Mojo::Base -strict;

use Test::More;
use Test::Mojo;
use feature 'say';

my $t = Test::Mojo->new('Site1');
   $t->ua->max_redirects(2);

my $email = 'test1@test.com';
my $emailpass = 'test1_pass';
my $server = 'westwind.backbone.site';

subtest 'Top page' => sub {
    $t->get_ok('/')->status_is(200)->content_like(qr/Mojolicious/i);
};

subtest 'Login' => sub {
  # 認証にcoolieが必要なのでproxy経由のパスを指定しないと動作しない secure属性

  #  my $tx = $t->ua->build_tx(POST => '/signinact' => form => { email => $email, password => $emailpass });
    ###  $tx->req->cookies({name => 'user', value => 'sri'});
  #     $t->request_ok($tx)->status_is(200);

    $t->post_ok("https://$server/signinact" => form => { email => $email, password => $emailpass })
      ->status_is(200)
      ->content_like(qr/OPEN the Menu!/);

  #  my $content = $t->tx->res->body;
  #  say $content;

  #  my $cookies = $t->ua->cookie_jar->all;
  #  for my $i (@$cookies){
  #      say $i;
  #      say $i->name;
  #      say $i->value;
  #  }

};


subtest 'Sessionid Change' => sub {

    $t->get_ok("https://$server/menu");

    my $cookies = $t->ua->cookie_jar->all;
    my $sid;
    for my $cookie (@$cookies){
        if ($cookie->name eq 'site1'){
            $sid = $cookie->value;
            say "SID: $sid";
        }
 
    } # for

    my $newsid = $sid; # 初期
    my $cnt = 0;

    # 1/1000で一致する想定
    while ( $sid eq $newsid ) {
        $cnt++;
        $t->get_ok("https://$server/menu");

        my $newcookies = $t->ua->cookie_jar->all;
           for my $cookie (@$newcookies){
           $newsid = $cookie->value;
       #    say "NEWSID: $newsid";
           }
       # sleep 1;
    }
    say "CNT: $cnt"; 

    ok($cnt,'pass');    

};




done_testing();
